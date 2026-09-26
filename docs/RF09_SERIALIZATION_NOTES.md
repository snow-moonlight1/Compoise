# RF09 C1/C2 序列化优化 — 实施与测量记录（2026-09-26 收口）

**状态：C1+C2 已实施；测量与验证已在独占、串行条件下重做完毕；两笔提交落在 `codex/rf09-serialization`（未 push、未 amend、未切 main、未改共享文档）。**

**本包未做任何真机/桌面手工验收。** 全部数字来自 `flutter test` JIT + `SharedPreferences` 内存 mock，不含 Android/Windows 真机落盘，设备端收益归 RF10（见 §4）。

- 工作树：`D:\Dev_project\martix-rf09-serialization`，分支 `codex/rf09-serialization`
- 基线：`main / 22aa43d6f88bcbbb9efd778aef23e023454975e0`（本包在其之上追加）
- 冻结对照树（before 用）：`D:\Dev_project\martix-rf09-base`（detached @ `22aa43d`，已 `pub get`）→ **测量完成后已 `git worktree remove --force`，未留下游离工作树**
- 固定 SDK：`D:\Dev_SDKs\Flutter_3.32.8`
- 提交：
  - `43b16cb` `test(rf09): 锁定落盘字节与校验和语义` — 锁测试 + bench 工具，**在改 `lib/` 之前先 31/31 全绿**
  - 本文件所在的第二笔：`perf(rf09): 去掉被丢弃的整库编码并合并校验和编码`

## 1. 已锁定与已实施

### 1.1 基线行为锁（31 项，改动 `lib/` 之前全绿）

`matrixflow-native/test/rf09_serialization_test.dart` 的 golden 常量是**从改动前的生产代码实测捕获**的（不是手算）：

```bash
flutter test --no-pub test/rf09_serialization_test.dart --dart-define=RF09_CAPTURE=1  # 打印 RF09GOLDEN 行
flutter test --no-pub test/rf09_serialization_test.dart                                # 31/31
```

锁的内容：

| 组 | 锁什么 |
|---|---|
| S1 | 已提交槽的**逐字节**内容（revision 1 与 2 两份完整 payload 字符串 + `check` 整数）、写序（槽→指针→5 个镜像键，`has-seen-onboarding` 走 `setBool` 不进 `saveWriter`）、1000 条库的 payload 字节数/指纹/`check`、`scrubCredentials` 重写后的两槽与镜像字节 |
| S2 | `load()` 的每条拒绝路径与**判定顺序**：`Invalid save pointer` / `Missing committed batch` / `Invalid committed batch` / `Incomplete committed batch` / `Committed batch checksum failed`；键完整性检查**先于**校验和；values 内含非字符串时抛的是 `TypeError`，而 `Store.init` 的 `catch (_)` 同样把它归类为损坏并进入恢复页 |
| S3 | 槽写被拒 / 指针写被拒 / 槽写抛异常 / 指针落地后抛异常（算已提交）/ 单个镜像键被拒不影响提交；`flush()` 真正等待被阻塞的提交；**`retrySave()` 在完全干净时仍产生一次新提交**（锁住 C1 的风险点：它依赖 `_markDirty()` 无条件 `_dirtyRevision++`） |
| S4 | 一次任务编辑＝恰好一个批次、写字节序不变；**设置项改动仍重写整库 tasks 镜像**；建板一次命令一个批次；不可用 Store（`ready=false` / `hasStartupRecovery`）不写任何东西；导入批次被阻塞时并发编辑落在**其后**且不与导入批次混合 |

> 两条**不依赖 golden 字面量**的字节同一性论据也在该文件里，改动后仍绿：
> `expect(payload, referencePayload(1, values))`（测试内独立实现的「旧式装配」：先 `jsonEncode({'revision','values'})`、再对 body 求 Adler、再在末尾 `}` 前插 `,"check":N`），以及「每个 value 的 `jsonEncode` 结果作为子串出现在 payload 中」。

### 1.2 C1 最终形态（已实施）

`matrixflow-native/lib/storage.dart`：

- `_write(String key, String value)` → `void _markDirty()`，四个门禁（`!ready || _disposed || hasStartupRecovery || credentialError != null`）、`_dirtyRevision++`、`_scheduleCommit()` 原样保留；
- `_saveTasks/_saveBoardsMeta/_saveConfig/_saveSettings` 改为单行 `_markDirty()`，**方法名与全部调用点不变**；
- `completeOnboarding` / `resetOnboardingForTest` / `retrySave` 三处原 `_write(key, …)` 调用改为 `_markDirty()`；
- `_saveBoardsMeta()` 原来调 `_write` 两次（boards + activeBoard），现在一次 → **单条命令的 `_dirtyRevision` 增量可能从 2 变 1**。无测试读取 `_dirtyRevision`；`_rebaseImport` 对无 payload 的 plan 用 `baseRevision == _dirtyRevision` 判等（只要「有变更就变值」仍成立），故可接受；S3/S4 的批次计数与重启回读测试是兜底。

### 1.3 C2 最终形态（已实施）

`matrixflow-native/lib/save_protocol.dart`：整库 `values` 只编码一次，`body` 不再物化，payload 由片段拼出；**写入、读取、scrub 三处共用同一 helper**。

```dart
static String _bodyPrefix(Object? revision) =>
    '{"revision":${jsonEncode(revision)},"values":';
static String _bodyPayload(String prefix, String valuesJson, int check) =>
    '$prefix$valuesJson,"check":$check}';
static int _bodyChecksum(String prefix, String valuesJson) { /* Adler-32，分段喂入，末尾补 '}' */ }
```

改动前 → 改动后（同一个 body 的字节）：

```dart
// 前：body 编码一次只为喂 _checksum，payload 再整库编码一次，_checksum 内部 utf8.encode(body) 又整库一次
final body = jsonEncode({'revision': next, 'values': values});
final payload = jsonEncode({'revision': next, 'values': values, 'check': _checksum(body)});

// 后：整库 values 只编码一次，body 不再物化，payload 由片段拼出
final valuesJson = jsonEncode(values);
final prefix = _bodyPrefix(next);
final payload = _bodyPayload(prefix, valuesJson, _bodyChecksum(prefix, valuesJson));
```

要点与坑：

1. **`load()` 与 `scrubCredentials` 复用同一个 `_bodyChecksum`**，否则写读两侧漂移会让老用户库被判损坏；`load()` 也走 `prefix + jsonEncode(values)` 形式。
2. Adler-32 定义未变：`(b<<16)|a`，模 65521，对 **UTF-8 字节**；`utf8.encode` 那段是校验和的固有成本，省不掉（省掉的只有第二次 `jsonEncode`）。
3. 逐片段 `utf8.encode(prefix)` + `utf8.encode(valuesJson)` + 一个 `}` 字节，与整体一次 `utf8.encode(body)` 等价，可分段喂进 Adler 循环。
4. `load()` 的字段类型检查与键完整性检查**位置未动**（仍先于校验和），所以 S2 的判定顺序与 `TypeError` 路径不变。
5. `scrubCredentials` 的 revision 走 `_bodyPrefix(Object?)`（内部仍 `jsonEncode`），**没有**收紧成 `int` 强转，以便对「槽里 revision 不是 int」这种损坏数据保持与改动前一致的行为（原来按原值重新编码）。

## 2. 本轮重做的测量与验证

### 2.0 方法与可复现命令

前置条件：机器上没有别的 `flutter_tester` / `dart` 在吃 CPU（进程 CPU 时间两次采样确认增量为 0 才开跑）。**改动 `lib/` 期间不启动任何测量**；每一条测量独占、串行。

```bash
# before：冻结树（先复制本树的 bench 过去，逐字节同哈希）
flutter test --no-pub test/review/rf09_serialization_bench.dart --dart-define=RF09S_REPS=7
flutter test --no-pub test/review/rf09_measurement.dart --dart-define=RF09_ONLY=io,e2e --dart-define=RF09_REPS=7
# after：本树跑同样两条
```

每侧 bench 跑 2 遍、measurement 跑 3 遍；不一致的样本按污染丢弃（见 §2.3）。bench 旋钮 `RF09S_ONLY=format,protocol,command`、`RF09S_SCALES`、`RF09S_REPS`、`RF09S_WARMUP`；`sample()` 会连预热样本一起记入序列，bench 里用 `sublist(warmups)` 丢弃前缀，报告阅读时注意这一层。

### 2.1 字节同一性（机械证据，非人眼比对）

`f1_slot` 在四个规模上 **before 两遍 / after 两遍完全相同**（`payload_bytes / payload_fp / check / mirror_bytes / mirror_fp`）：

| tasks | payload_bytes | payload_fp | check | mirror_bytes | mirror_fp |
|---|---|---|---|---|---|
| 3 | 2030 | 1821304614 | 1483526255 | 949 | 912455681 |
| 100 | 49966 | 1860566894 | 1031006322 | 45151 | 127512952 |
| 1000 | 474696 | 577447677 | 1688904328 | 435672 | 132045484 |
| 10000 | 4753967 | 1924408346 | 431073835 | 4376409 | 1811674692 |

同批的另外三处：

- `f1_reload`：四规模 × 四遍，`load()` 全部成功且 `loaded_values_fp` 完全一致（3→1390005189、100→1987910564、1000→18727156、10000→429076080），即 after 的读取侧能接受同样的字节；
- `f4_scrub`：四遍全同（`before_fp=205651113`、`slot_a_bytes=914`、`slot_a_fp=580619272`、`slot_b_fp=1586390891`、`mirror_fp=1440640056`、`check_a=47071778`、`loads_after=true`、`key_removed=true`），**`scrubCredentials` 重写后的字节没变**；
- `f3_command`：同规模同 scenario 的 `payload_bytes` 与 `check_last` 在 before/after 四遍之间一致（例如 1000 local_edit 都是 474552 字节 / `check_last=2456375556`，10000 local_edit 都是 4753853 字节 / `check_last=3857278936`）。

`test/rf09_serialization_test.dart` 的 11 个 golden 常量（含 1000 条库的字节数/指纹/`check`）也逐位未变，31/31 全绿。

### 2.2 提交耗时 before/after（bench `f2_protocol_commit`）

`cpu_before_first_write`（`commit()` 调用 → 首次槽写，即 C2 针对的编码链；中位数 µs，两个数值＝两遍）：

| tasks | before | after | 变化 | 波动（IQR/中位） |
|---|---|---|---|---|
| 3 | 209 / 243 | 115 / 114 | −45% / −53% | before 2.61 / 0.39；after 0.44 / 0.41 |
| 100 | 2374 / 2694 | 1543 / 1607 | −35% / −40% | before 0.15 / 0.11；after 0.06 / 0.04 |
| 1000 | 30163 / 27859 | 16395 / 16682 | −46% / −40% | before 0.22 / 0.12；after 0.04 / 0.14 |
| 10000 | 262242 / 308842 | 131267 / 143123 | −50% / −54% | before 0.0 / 0.0；after 0.0 / 0.0 |

`commit_total`（含指针写与 5 个镜像写）中位数：1000 → 31852 / 29485 **→** 18459 / 19138；10000 → 277529 / 327201 **→** 143872 / 157114。

读法与如实说明：

- **小库（3 条）绝对值只有 0.1ms 量级，不构成用户可感知收益**，方向对但不必宣传；100 条也只有 ~1ms。
- 1000 / 10000 是收益面：约 **−40% ~ −54%**。before 两遍在 10000 上中位差 18%（262.2 vs 308.8ms），after 两遍差 9%，所以只声明方向与量级，不把个位数当结论。
- 数量级与改动的组成相符：Before 对整库做了 **两次** `jsonEncode`（body 一次、payload 一次）外加一次 `utf8.encode(body)`；After 只剩 **一次** `jsonEncode(values)` 加一次 `utf8.encode(valuesJson)` 与一次拼接，即「去掉一份整库编码与一份同尺寸临时字符串」。After 残留的 131–143ms@10k 主要是 `_snapshotValues`（每次提交仍要整库编码一次 tasks 镜像）、校验和的 UTF-8 遍历和 payload 拼接——那属于明确不做的 C4/C5 范围。
- **对既有 M2 结论的校正**：`docs/RF09_MEASUREMENT.md` M2 的 body+payload+checksum 理论值 27.5ms@1k / 349ms@10k，本轮 before 实测 27.9–30.2ms@1k、262.2–308.8ms@10k，同一量级（1k 差 ≤10%）。**此前记录的 67,558µs@1k / 519,545µs@10k 确系并发污染，不应再被引用。**

### 2.3 真实 Store 命令路径（bench `f3_command` 与 `rf09_measurement.dart` 佐证）

`f3_command` 的 `pre_io`（命令 → 首次槽写，中位数 µs，两个数值＝两遍）：

| tasks | scenario | before | after |
|---|---|---|---|
| 3 | local_edit | 534 / 789 | 352 / 444 |
| 3 | settings_toggle | 480 / 551 | 251 / 262 |
| 100 | local_edit | 4635 / 5685 | 2584 / 3054 |
| 100 | settings_toggle | 3873 / 4384 | 2510 / 2860 |
| 1000 | local_edit | 42821 / 48014 | 23167 / 27770 |
| 1000 | settings_toggle | 33582 / 41315 | 23340 / 30610 |
| 10000 | local_edit | 440335 / 494645 | 248740 / 270771 |
| 10000 | settings_toggle | 356609 / 406179 | 229392 / 242308 |

`f3_command` 的 `visible`（同步返回 → flush 完成）：10000 local_edit 456581 / 513964 **→** 262638 / 287746；10000 settings_toggle 383378 / 426719 **→** 242895 / 256748。

**C1 的可见收益面**是命令的同步返回段（`sync`，`updateTask` 调用本身）：10000 local_edit 78622 / 91553 **→** 15505 / 19185；1000 local_edit 8091 / 9811 **→** 2601 / 2672。因为改动前每次编辑都要在同步段里 `jsonEncode` 一整库 tasks 再去丢掉。设置类命令本来就不编码 tasks，所以 10000 settings_toggle 16136 / 19388 **→** 15487 / 16107 基本不变（噪声内）。注意：`f3` 的 after 是 C1+C2 合计，单独的 C1 分量没有单独 A/B（C1 与 C2 未拆两次测量）。

`rf09_measurement.dart`（只读复用）的佐证：

- `m3_commit_io` 的 `cpu_before_first_write`（**每规模单样本**，噪声最大）：before 三遍 3=6562/7484/6678、100=11391/10745/11043、1000=40876/41510/51044、10000=424697/487783/464974；after 的第 2/3 遍 3=8757/7906、100=7529/7306、1000=26684/27230、10000=221388/226828。**after 第 1 遍（15868/14618/52263/581882）四档同时偏高、同批 m4 也整片偏高（壁钟 34.7s vs 后两遍 18.7/18.0s），按污染丢弃**，与 §2.0 的「不一致即污染」规则一致。
- `m4_command` 的 `pre_io_med`：1000 local_edit 34949/37807/44024 **→** 22301/24196；1000 settings_toggle 35598/36513/36482 **→** 20277/23562；10000 local_edit 421763/468897/421262 **→** 282691/256087；10000 settings_toggle 349286/352455/382996 **→** 274450/241412。3 条一档 463–557 ↔ 457–658，**无变化**，与「小库无显著收益」一致。

### 2.4 验证清单结果（全部独占串行）

| 项目 | 结果 |
|---|---|
| `flutter test --no-pub test/rf09_serialization_test.dart` | **31/31**，golden 未变 |
| 可靠性定向：`os05_startup_recovery` `os06_os07_transaction` `os08_os09_credential` `rf02_import_commit_race` `rf03_credential_close` `rf04_backup_contract` `os15_desktop_exit` `rf08_reminder_retry` | **106/106** |
| 全量 `flutter test --no-pub` | **753/753**（基线集成态 722 + 本包 31） |
| `flutter analyze --no-pub` | **No issues found!**（见下条说明） |

两条需要交接注意的点：

1. **golden 字面量的转义**：31 项锁测试的常量原本是从捕获输出直接粘回源码的，`jsonEncode` 打的 `\"` 全被写进单引号字面量，导致 `analyze` 从 0 变成 **466 条 info**（464 × `unnecessary_string_escapes`，外加 1 × `unnecessary_const`、1 × `prefer_function_declarations_over_variables`）。已用一次性脚本把 5 个字面量按最小转义重写（只删冗余 `\"`，保留 `\\` / `\n` / `\t` / `\uXXXX` / `\$`），并用 `--dart-define=RF09_CAPTURE=1` 重新捕获、与文件逐字符比对 **11/11 完全一致**；同时把 `reportGolden` 的打印改成最小转义 Dart 字面量（新增测试内 `dartLiteral`），避免下次再捕获时重新引入同类 lint。**常量的字符串值没有任何变化**，由 31/31 与 11/11 比对双重兜底。
2. **未做的测量**：`RF09_ONLY` 的其余小节（`dead,encode,query,mem,build`）本轮没跑，`io,e2e` 之外的旧数字仍来自 `docs/RF09_MEASUREMENT.md`，不在本包重新背书。

## 3. 明确不做

C3（按键条件写镜像）、C4（跨提交缓存未变键）、C5（读侧缓存只读视图/id 索引）、C6（改成按键增量提交）——理由见 `docs/RF09_MEASUREMENT.md` §7。不改 `backup_export.dart`、`l10n.dart`、桌面壳、并发包文件，不改 AGENTS/HANDOFF/CHANGELOG/ARCHITECTURE/返修计划，不改 `test/review/` 下他人探针（`rf09_measurement.dart` 只读复用）。

## 4. 已知的验收边界（不得写成已完成）

全部数字是 `flutter test` JIT + `SharedPreferences` 内存 mock，**不含 Android/Windows 真机 SharedPreferences 落盘**；Release/AOT 只有 `RF09_MEASUREMENT.md` §6 的纯 Dart 编码段对照。设备端收益归 RF10。本包**未做任何真机/桌面手工验收**，也未测系统级退出。字节同一性证明的是「磁盘格式没变、老库仍可读」，不等于「已有用户库在真机上被迁移验证过」——本包不写盘迁移，不需要迁移。

`windows/flutter/generated_plugin_registrant.{cc,h}`、`generated_plugins.cmake` 只有行尾差异，**保持未 staged**。
