# WP18-R：可选同步的离线冲突原型（实验包记录）

基线 `459f9a28cefdcac9196825b2d4ac70250dbf3b8d`，分支 `codex/wp18-r`，工作树 `D:/Dev_project/martix-wp18-r`。
本包只做隔离技术原型：没有产品入口、没有后台任务、不接 Store/账号/云盘，也不声明当前手工备份等于同步。

## 1. 交付与边界

新增文件（仅这些）：

- `lib/experiments/wp18_sync/`：`digest.dart`、`snapshot.dart`、`plan.dart`、`planner.dart`、`applier.dart`、`transport.dart`、`demo_fixtures.dart`
- `tool/wp18_sync_lab.dart`：可执行冲突模拟器（纯 Dart，`dart run` 即可）
- `test/wp18_sync_conflict_test.dart`、`test/wp18_sync_policy_test.dart`、`test/wp18_sync_transport_test.dart`、`test/wp18_sync_contract_test.dart`
- `docs/WP18_R_NOTES.md`（本文件）

未改动：Store、SaveProtocol、模型 schema、备份/导入、主导航、设置、生产网络代码、`pubspec.yaml`/`pubspec.lock`、`test/helpers.dart`、共享 README/ROADMAP/导航/发行版本/模型锁。
源码里的字节上限（8 MiB）、深度上限（12）、记录数量上限、确认与提交流程都按原样读取校验，本包不放宽：`test/wp18_sync_contract_test.dart` 用 `ImportPreflight.maxFileBytes/maxDepth/maxBoards/maxTasks/maxScheduleItems` 做了钉住断言。

`flutter pub get --enforce-lockfile` 后 `pubspec.lock` 无差异；工具生成的 `windows/flutter/generated_*`（行尾差异）与新增的 `linux/flutter/generated_*` 均留在工作区未提交。

## 2. 输入、输出与判定

输入是同一基线上的两份合成 v3 库快照（本机 + 对端）。两种读取形状：

| 形状 | 含义 | 能推出删除吗 |
| --- | --- | --- |
| `presenceOnly` | 今天手工导出的 v3 文件 | 不能。缺失只表示缺失 |
| `tombstoneAware` | 实验信封 `wp18-sync/0`：`library` 仍是普通 v3，外层带设备身份、快照序号、墓碑和每条记录的计数器 | 只在有墓碑时表示删除 |

输出是可审查的冲突计划（`SyncPlan`）：每个分歧记录一条决定，标注 `auto`/`pending`/`blocked`、`kind`、`reason`、基线/本机/对端内容摘要、字段级差异、建议动作、被谁阻塞，以及每条决定被哪个 pass 改写过（`history`）。合并结果只写成调用方指定目录下的文件，绝不写 SharedPreferences。

分类覆盖：删除/编辑冲突、同 ID 分叉、不同 ID 内容重复、并发完成、父子（子项换父任务）、板引用、日程关联（时间块/事件、悬空引用、kind 变化）、`plannedDate`/`deadline`/时区、未知字段、子项顺序、设置与 AI 配置整块分歧、凭据、设备计数器相等造成的排序不可判定。

## 3. 引擎不会自己做的决定（安全规则）

1. 缺失不等于删除。`presenceOnly` 输入下任何单边消失都是 `pending`，测试 `a plain v3 export never produces an automatic deletion` 钉住这条。
2. 待决项不改本机内容。测试遍历全部场景断言：非 `auto` 的决定对应的记录在合并结果中与本机一致。
3. 不复活用户删除。`deleteEdit` 永不自愈；`preferPeer`/`preferLocal` 都被拦住并写明 “Withheld under …”，只有显式 `allowResurrection` 或人工 `Override.restore` 才写回，且结果里出现 `resurrected` 条目和报告行。
4. 不制造悬空引用。删除会让仍存活的子项/日程失去归属时，删除被 `blocked`（`deletionWouldOrphanDependents`）；对端新增日程指向已删任务时被 `blocked`（`referencedRecordNotSettled`），也不把孤儿改成事件。人工强行 `drop` 时，合并自检报错，CLI 以退出码 1 结束而不是交付坏库。
5. 未知字段不解释、不带走。`digest` 包含未知字段，因此“只加了一个不认识字段”的对端也会被视为改动并进 `pending`；产品侧 `ImportPreflight` 会对同一字段报警告，两边结论一致。
6. `aiConfig.customApiKey` 在读入时即丢弃（空串不算密钥），计划文本、合并 v3、合并信封中都不出现密钥字段或值。
7. 每条记录的计数器是设备本地序号。计划 JSON 带 `clockCaveat`，本机/对端计数相等时明确标注 “ordered by device id, which is deterministic but not a claim about time”。当前 `Store._taskSeq`/`_scheduleSeq` 和 `SaveProtocol.revision` 都不构成全局同步时钟：前两者是本机每记录递增的命令序号，后者是本机提交槽序号；跨设备只比较它们会得出错误顺序。

`plannedDate`/`deadline` 是本地民历零点（`docs/BACKUP_FORMAT.md`）。两个时区对同一天写出不同 epoch 毫秒是必然的，所以字段级比较先归一到民历日：同一天不算冲突（`sameCivilDayDifferentZone`，自动保留本机表示），真换天才进 `pending`。日程的 `timeZoneId` 变更则视为真实改动。

## 4. 策略演示（同一份库，五种选择）

`dart run tool/wp18_sync_lab.dart policies <scenario>` 对每个场景打印 5–7 行对照表：`holdPending`、`preferLocal`、`preferPeer`（含 `resurrect=on` 两种）、`fieldwiseAuto`、`manual`，随后是 `auto/pending/blocked/applied/records/resurrected/clean` 计数。示例（`delete-edit-peer-deleted`）：不放开守卫时三种“选边”策略都把删除/编辑留在待决，本机内容不变；`preferPeer + allowResurrection` 让删除生效（记录数 2→1）；`preferLocal + allowResurrection` 写回并标记 1 次复活。

命令行：

```
dart run tool/wp18_sync_lab.dart list
dart run tool/wp18_sync_lab.dart plan <scenario> [--policy P] [--presence M] [--resolve key=action]
dart run tool/wp18_sync_lab.dart policies <scenario>
dart run tool/wp18_sync_lab.dart catalog            # 33 个场景逐条核对预期
dart run tool/wp18_sync_lab.dart dump <scenario> --out DIR
dart run tool/wp18_sync_lab.dart files --base A.json --local B.json --peer C.json [--out DIR]
dart run tool/wp18_sync_lab.dart transport [--root DIR] [--keep]
```

`files` 既吃实验信封也吃普通 v3 文件；普通 v3 会被标为 `file-base/file-local/file-peer` 设备并共享一个时钟——这正是“手工备份不足以做同步”的可复现证据。

## 5. 最小 transport 接口与能力边界

`SyncTransport`：`capabilities()`、`put(snapshot, expectedDigest, operationId)`、`pull(exceptSnapshotIds)`、`currentDigest(deviceId)`、`listDevices()`。
能力位：条件写（`supportsConditionalPut`）、服务端保存删除标记（`serverKeepsTombstones`）、变更流（`supportsChangeFeed`）、单条字节上限、是否需要账号、是否仅在线。`shortfalls()` 把缺失能力翻译成后果（陈旧覆盖、第三方加入后复活删除、每次整库搬运、与“无账号”立场冲突、离线不可用）。

`LocalDirectoryTransport` 用临时目录假扮服务端，注入故障已验证：离线、写失败后重试、重复投递幂等（`operationId`）、中途取消后重放为幂等、远端已被改写时条件写拒绝（`remote-diverged`）、文件被截断或库内容被改（重算内容摘要失败并从计划输入中剔除）、超上限拒收。

摘要直接复用产品里已有的纯 Dart SHA-256：`lib/recovery_text.dart` 的 `recoverySha256Hex`（恢复归档的 `archiveId` 与 `prefixSha256` 用的就是它），所以信封内容标签与备份恢复校验同源，本包没有引入任何依赖（锁文件里也没有 `crypto` 包）。`test/wp18_sync_contract_test.dart` 断言两者对同一输入给出同一个 64 位十六进制串。

## 6. 公开跨平台协议研究（只引用原始文档）

下面引用的句子与编号取自 rfc-editor.org 上 RFC 4918、RFC 6578、RFC 4791 的正文（2026-10-04 抓取），没有使用二手摘要或第三方博客；未实测任何真实提供方。

选项 A：WebDAV 文件同步。RFC 4918 定义 `PUT/DELETE/MKCOL/PROPFIND` 等方法与 `DAV:getetag`；强 ETag 断言字节一致（对“同 ID 分叉”判定有用），条件写靠 `If-Match`/`If-None-Match`，官方建议写入按 lock → retrieve → write → unlock 顺序以避免并发覆盖。增量靠 RFC 6578 的 `sync-collection` REPORT：`sync-token` 是客户端必须当作不透明字符串的合法 URI；被移除的成员以 `<D:status>404 Not Found</D:status>` 报告；同一 URL 在一次响应中只出现一次；结果被截断时用 207 并在请求 URI 上给 507，配 `DAV:number-of-matches-within-limits` 以便分页；token 无法识别时触发 `(DAV:valid-sync-token)` 前置条件，客户端回退到空 token 做整集合再同步。
适配代价：任务库要按记录切文件（1 任务 1 资源）才能取得增量与冲突可见性；删除仍需自己保存墓碑，协议本身不告诉客户端“为什么少了这条”。云盘类提供方对 `sync-collection`/Delta 的支持参差，实际会退化为整库传输（当前 v3 上限 8 MiB）。依赖：现有 `http` 足够，无需新包；服务成本：用户自备 WebDAV 端点，或我们托管（则引入账号、配额、可用性责任）。

选项 B：CalDAV 记录级日程同步。RFC 4791 要求日历集合中每个资源承载单一组件类型（一个 VEVENT/VTODO 一个资源），所有日历对象资源必须有强 `DAV:getetag`，创建用 `If-None-Match: *`、更新用带具体 ETag 的 `If-Match`；`calendar-query` 与 `calendar-multiget` REPORT 为必选；§8.2 明确“客户端可以离线存放日历对象并在稍后同步”，即增量与冲突控制留给客户端引擎；媒体类型必须是 iCalendar（文档正文引用 RFC 2445），且集合内对象不得带 `METHOD` 属性（调度状态由客户端处理）。
适配代价：任务/板/日程模型要映射到 VTODO/VEVENT + VALARM，含 `plannedDate`、`urgencyMode`、`tags`、`notesMarkdown` 等自有语义；往返映射会引入新的丢失面，与“不削弱现有 v3 契约”的约束直接冲突。依赖：需要 iCalendar 编解码与集合发现（`rfc6352` XCAP）实现或第三方包，均不在当前锁文件内；服务成本：需要支持 CalDAV 的账号（自建或用户已有），账号体系正是 WP18 之后才该讨论的东西。

建议：先把 A 的“文件级 + 我们自己带墓碑与设备身份”作为下一候选做更小原型（不引入新依赖、不需要账号、可离线跑，且与本包计划/合并逻辑直接复用），但不要在用户决策前上线任何服务。B 只在“愿意把任务模型改写成 iCalendar 并接受映射损耗”时才值得，现在不建议。

## 7. 给用户/集成端的决策清单

1. 同步是否必须完全无账号？若允许用户自备端点，A（WebDAV/文件夹）是最小步；若要求开箱可用，就必须决定托管成本与隐私声明改写。
2. 删除证据放哪里：导出文件加信封（本包形状），还是记录级元数据（改动 schema）？前者不动 v3，后者更省事但要过兼容门禁。
3. 冲突默认策略选哪种：`holdPending`（永不猜，代价是用户要处理待决）、`fieldwiseAuto`（多数单边改动能自动合），还是 `prefer*`（快但会覆盖一方的编辑）。本包能并排打印，用来做决定而不是用文字讨论。
4. 待决项呈现方式：导入预检已有预览，同步需要“逐项确认/整体保留本机/整体取对端”三类入口，涉及设置页与导航（本包未做）。
5. 设置与 AI 配置是否参与同步：当前实验把它们作为整块待决，密钥一律不过境。要不要同步偏好，等于要不要引入密钥托管讨论。
6. 传输安全层级：SHA-256 标签已在仓库内（恢复归档同源），能发现损坏与改写，但不提供保密性。是否要求端到端加密、谁的密钥、密钥丢失后的恢复路径，都属于账号/密钥托管讨论，本包没有实现也没有评估。
7. 记录数量与体积：整库信封在当前 8 MiB 上限内，但多设备并发使用大库时“每次搬整库”是否可接受（决定是否要求 `supportsChangeFeed` 能力）。

## 8. 验证记录

- `flutter pub get --enforce-lockfile`：退出 0；`pubspec.yaml`/`pubspec.lock` 无改动（`git diff --name-only` 空）。
- 工具链校验：`toolchain.json` pin Flutter 3.32.8 stable / revision `edada7c56e…` / Dart 3.8.1；本机 `D:/Dev_SDKs/Flutter_3.32.8/bin/flutter --version` 输出 3.32.8 / `edada7c56e` / Dart 3.8.1，匹配。缓存、日志、临时库、输出全部在本包私有根 `D:/Dev_project/martix-wp18-r-private`（`PUB_CACHE` 指向其中 `pub_cache`）。
- `dart run tool/wp18_sync_lab.dart catalog`：退出 0，`scenarios=33 mismatches=0`。
- `dart run tool/wp18_sync_lab.dart transport`：退出 0，`transport failures: 0`（离线/重试/幂等/取消/条件写/损坏/超限 7 类）。
- `dump` + `files` 往返：退出 0，写出 `wp18_plan.json`、`wp18_plan.md`、`wp18_merged.v3.json`、`wp18_merged.envelope.json`；同一场景改用普通 v3 + `--presence presenceOnly` 时不写任何文件、0 项自动应用、2 项待决（删除无法由缺失证明）。
- 本包定向回归（逐个文件单独跑，数字取各自末行 `+N`）：见 §10 表。
- `flutter analyze --no-pub`（全仓）与默认全量 `flutter test --no-pub`：见 §10。

未验证 / 明确不声称：

- 没有真机、没有云盘、没有账号、没有 WebDAV 服务器；`LocalDirectoryTransport` 是目录假扮，不能当作任何真实提供方的兼容证据。
- 没有 Store/SaveProtocol 接线：合并结果只是文件，未经过提交槽、确认流程或恢复锁，因此“应用能安全写入”不在本包结论内。
- 没有跨进程/跨设备真机同步验证；没有后台任务、通知重排与 `flutter_local_notifications`/`timezone` 的真实 IANA/DST 验证（实验用固定偏移表示时区）。
- 内容标签用的是仓库内 SHA-256，能发现损坏与改写；但没有做端到端加密、服务器鉴权、重放保护或对抗主动构造碰撞的安全评估。
- 大库性能未测：33 个场景是合成小库，没有 10k 任务级压测；`sync-collection` 截断/分页只在能力层描述，没有跑通真实响应。

## 9. 跨界缺陷与建议（留给集成端，不在本包修改）

1. `plannedDate`/`deadline` 记录的是本地民历零点，但快照里没有“记录所属时区”。任何跨设备合并都会把它们当整数比较。建议在下一包决定：要么在同步侧带设备时区上下文（本包用 `zoneOffsetMinutes` 演示），要么把计划日改成民历日字符串 + 显式时区；现在这样会造出假冲突。
2. 子项顺序是位置性的（v3 数组下标）。记录级同步会丢掉顺序，除非给子项加显式 `position`/排序键。本包把“内容相同、顺序不同”标为待决（`reorderedOnBothSides`），但这只是暴露问题，不是解决。
3. `Store._taskSeq`/`_scheduleSeq` 与 `SaveProtocol.revision` 都是本机序号，不能当同步时钟；若要做“上次同步基线”，需要独立的、带设备身份的每记录标识（本包用信封的 `recordState` + 墓碑演示最小形态）。
4. v3 导出文件没有设备/快照身份。手工导出可以当同步输入，但缺失即待决；如果希望同步能表达删除，需要显式信封或 schema 变更，并请由集成端在 `docs/BACKUP_FORMAT.md` 判定是否升版本。
5. `recoveryPending` 是本地恢复游标：跨设备合并它没有意义。建议在同步范围里显式排除（本包把它列入设备本地字段）。
6. 设置与 AI 配置在导入侧已是“整块”语义（合并不导入设置/配置），同步也要保持整块决策，否则会出现“半套偏好”的新坏状态。

## 10. 本包套件计数（单独跑，读各自末行 `+N`）

| 文件 | 结果 |
| --- | --- |
| `test/wp18_sync_conflict_test.dart` | 40 passed |
| `test/wp18_sync_policy_test.dart` | 21 passed |
| `test/wp18_sync_transport_test.dart` | 11 passed |
| `test/wp18_sync_contract_test.dart` | 15 passed |

共 87 个用例，全部为合成数据或临时目录，默认不下载模型、不启动设备、不联网。

门禁：

- `flutter analyze --no-pub`（全仓）：退出 0，`No issues found!`
- `flutter test --no-pub`（默认全量）：退出 0，`+1501 ~11`，无 `[E]`。基线 1414 + 本包 87 = 1501，说明默认套件既没有被本包改动，也没有被削弱；11 个条件跳过是既有项。
- 构建入口未变：`lib/main.dart`、`lib/screens`、`lib/widgets`、`lib/services`、`integration_test/`、各平台 runner 目录相对基线无差异；除本包文件与工具/测试生成的 `windows|linux/flutter/generated_*`（未提交）外没有其它改动。
- 隔离性：只有 `tool/wp18_sync_lab.dart` 与 4 个 `test/wp18_sync_*` 引用 `lib/experiments/wp18_sync/`，产品代码零引用，因此实验不会被应用入口带入发行包。
