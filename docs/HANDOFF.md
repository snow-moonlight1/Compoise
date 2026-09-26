# 项目交接文档（HANDOFF.md）

## 当前状态：导入目标语义补丁（2026-09-26）

- 修复设置页“合并到当前”实际按备份 `boardId` 新建任务板造成的歧义。导入现在明确提供三项：按备份任务板合并、选择现有任务板合并、覆盖所有。
- 按备份任务板合并会复用同 ID 任务板、只新建缺少的任务板；选择现有任务板合并会把所有导入任务改挂到用户选中的现有板，不创建备份板，也不导入设置/AI 配置；覆盖所有直接替换备份中存在的任务板、任务、设置和 AI 配置，凭据仍按原有显式确认处理。
- 目标板选择保存在 `ImportPlan`，提交时重新预览也保留该选择；目标板消失、冲突或结果库超限时整笔失败。多卷按顺序导入到现有板会复用同一板并跳过相同记录。
- 新增 [RF11 导入目标回归](../matrixflow-native/test/rf11_import_target_test.dart) 8 项；集成态固定 SDK `flutter test --no-pub` **795/795**，`flutter analyze --no-pub` **0 issues**。设备上的新三选一界面和多卷导入仍需在已安装的 Android 测试包上人工复测。

## 当前状态：RF08 问题生命周期与 RF10 Android SAF 验证集成（2026-09-26）

- 从干净的 `main / 76a8201` 合入 RF08 `038a818` 与 RF10 `84f4716`；前者修改提醒账本、横幅和三语按钮，后者只新增 [Android SAF 实测记录](RF10_ANDROID_SAF_NOTES.md)。原工作树/分支未改，未 push，冻结端未改。
- RF08 的 `ledgerIssue` 改为按当前 read > write > overflow > damaged 状态推导；满额时保留被拒提醒身份，容量释放及协调轮将仍有效的提醒交回 64 项账本；损坏提示经用户明确“修复列表”重写成功或后续读到干净账本后清除。默认新增 11 项回归。合成测试不代表平台提醒必达；三语长文案在设备上的截断仍未验收。
- 固定 Flutter 3.32.8 集成态 `flutter test --no-pub` **787/787**、共享 RF-R01–07 与 RF08 探针 **9/9**、`flutter analyze --no-pub` **0 issues**。单包旧基线数字保留在各自记录中，不替代集成态结论。
- RF10 在 Android 16 原机与 Android 15 模拟器均验证隔离 Release 包的**单文件** SAF 保存、真实字节落盘与导入。原机导入两条合成任务后强停重启读回成功。此前 A6 “点按无反应”主要是坐标未命中，也可由凭据模态框的屏障点按取消复现；并非已证实的源码缺陷。原机用户应用 `com.matrixflow.app` 未被覆盖，测试包 `com.matrixflow.rf10saf` 已卸载，相关合成文件已删除。Android 多卷 SAF、真实 IME、凭据跨重启及 Windows 原生文件对话框仍未测。设备的 `wm size 1080x2400` / `wm density 420` 覆盖为更早阶段遗留，本轮未重置。
- 已从集成主线 `3d784df` 的 `git archive` 在仓库外构建 Android Release 测试包，仅在构建副本修改 `applicationId` 为 `com.matrixflow.review0926`、应用名为“MatrixFlow 测试 0926”。APK：`D:\Dev_project\matrixflow-review-3d784df-20260926.apk`，59,338,152 bytes，SHA-256 `7E7889BE5667926972B5870378303256AA808CC824A4470F384A18494EF0D36F`。`aapt` 已核对包名/入口，`apksigner` 已核对开发签名；这不是 OS26 正式发行签名。
- `adb -s 87d18604 install -r` 返回 `Success`，`pm path` 确认测试包与原有 `com.matrixflow.app` 同时安装，`am start` 后 `pidof` 返回进程。用户可从“MatrixFlow 测试 0926”图标开始手工验收；测试包使用独立空数据区，未覆盖正式应用或其数据。安装/启动检查不等于 Android SAF 多卷、真实 IME、凭据跨重启及提醒送达通过。
- 导入目标修复后的测试包已从 `4ed54d7` 构建完成：[matrixflow-review-4ed54d7-20260926.apk](D:\Dev_project\matrixflow-review-4ed54d7-20260926.apk)，59,338,138 bytes，SHA-256 `70BA43B5E98205D5820B6295A72ACEE4CD31C32C863D6D1B4D24B8BB15D19B9C`，包名仍为 `com.matrixflow.review0926`。构建时设备已从 adb 列表掉线，尚未安装这份新包；重新连接 `87d18604` 后执行 `adb install -r`，不清除测试数据或正式应用。

## 当前状态：RF04 超计数、RF08 提示、RF09 C1/C2、RF10 退出防护集成（2026-09-26）

- 从干净的 `main / 22aa43d` 依次合入 RF04 `ca4472a`、RF09 两笔 `43b16cb`/`970e3c7`、RF08 提示 `78aeaf9`、RF10 Windows 退出防护 `b7ca5ee`。产品文件互不冲突；独立 worktree/分支未改，未 push，冻结端未改。各包原始实施与局限见 [RF04](RF04_OVERCOUNT_NOTES.md)、[RF09](RF09_SERIALIZATION_NOTES.md)、[RF08 提示](RF08_LEDGER_UI_NOTES.md)、[RF10 退出](RF10_EXIT_GUARD_NOTES.md)。
- 固定 Flutter 3.32.8 集成态 `flutter test --no-pub` **776/776**、共享 RF-R01–07 与 RF08 探针 **9/9**、`flutter analyze --no-pub` **0 issues**。RF09 的墙钟测量未与全量测试并行；单包基线数字保留在各自记录中，不与集成态数字混用。
- RF04 现在在拆卷前按整库累计板/任务/子项数量；超出 500/10000/50000 时 `exportBackup()` 返回失败、不打开保存对话框、不写文件、不改库。第一阶段 RF10 在旧主线实测产生的超计数卷仍无法突破导入上限；本包阻止继续生成这种误称可恢复的卷集，**没有提供超计数历史库的无损备份途径**。
- RF09 C1 去掉提交前被丢弃的整库编码；C2 令保存、读取、凭据清理共用分段校验和装配。31 项默认锁测试包含旧格式逐字节 golden、损坏拒绝顺序、失败重试、退出与导入交错。合成 1000/10000 条库首次写入前 CPU 段下降约 40%–54%；3+2 小库的绝对收益约 0.1 ms，不作为设备手感结论。
- RF08 横幅已显示账本读取、写入、满额、损坏四类问题，读写失败可重试，英/中/日文案不承诺平台通知送达。满额或损坏 issue 尚无服务端自动清除时机，容量释放或坏数据被清理后可能继续显示旧提示；需按真实状态补齐。RF10 退出防护用合成 host 锁定完成/取消/失败交错，退出后不重建托盘或热键，`isApplyingSettings` 收口；Windows Release 新实现尚待手工验收。
- 后续可并行两个技术包：RF08 账本 issue 生命周期（满额/损坏提示何时清除且不隐藏未追踪提醒）、RF10 Android SAF 文件流程定位与隔离验收。二者完成后做 RF10 双端 IME/聚焦/文件操作及提醒路径的定向人工收口；不接管用户桌面鼠标键盘。超计数历史库的无损备份需要另定产品上限或迁移方案，不作为已解决功能。现有用户数据、真实密钥、正式签名与发布未用于本轮；OS26 独立待办。

## 当前状态：RF08、RF09 测量、RF10 第一阶段集成（2026-09-26）

- 从 `main / ac732b1` 顺序合入 RF08 `be57131`、RF09 测量 `b91da41`、RF10 第一阶段证据 `c56d556`，主线对应 `1ce5bd3`、`aa21e23`、`663660e`；独立 worktree 与分支未改，未 push。RF09 只增测量工具和记录，RF10 只增验收记录。
- RF08 的六次冷启动反例已从 `[1,1,1,1,1,1]` 修到 `[1,2,3,4,5,5]`；账本读写/满额有状态，退出保存屏障等待未落盘提醒。集成复核另外复现并修正两例：按通知 ID 清除与读取并发时磁盘旧记录会复活；读旧账本失败时新写入可能覆盖旧记录。两例均先红后绿，默认 RF08 回归现为 22 项。`ledgerIssue` 仍未接入用户可见横幅，双端未来提醒与点击回流未做设备验收。
- 固定 Flutter 3.32.8 集成态 `flutter test --no-pub` **722/722**、共享 RF-R01–07 与 RF08 反例探针合计 **9/9**、`flutter analyze --no-pub` **0 issues**。测试串行运行，避免墙钟基准受并发争用。
- RF09 [测量记录](RF09_MEASUREMENT.md)显示：3+2 小库量级没有可证实的保存性能收益，源码优化有据延期；10,000 条任务量级存在被丢弃的整库编码与校验和重复编码，建议限定 C1/C2、先锁定落盘字节与失败/重试语义。测量器是 JIT 加纯 Dart AOT 对照，不代表 Release 端到端手感。
- RF10 [第一阶段证据](RF10_PLATFORM_EVIDENCE.md)：Windows Release 真实磁盘和保护存储的凭据/导入/4200 条七卷恢复通过；Android Release 引导、软键盘、中文批量输入与设置页基础渲染通过。10,599 条历史库仍可成功导出两卷，却只恢复 7,066 条，第二卷因计数上限被拒，这是已实测的 RF04 残余缺陷。Windows 真实 IME/原生文件对话框、Android SAF/真实组字与凭据跨重启等仍未测；Android 隔离包 `com.matrixflow.rf10review` 暂未卸载。退出时 applySettings 的三种平台交错均未重建托盘或热键，但退出后 `isApplyingSettings` 会残留 true，源码也缺显式退出守卫。
- 下一批可并发开发四个文件所有权清晰的包：RF04 超计数导出契约、RF08 账本错误可见性、RF09 C1/C2 小范围优化、Windows 退出状态防护。先集成 RF04 后集成 RF09，最后再依据可用设备与人工操作完成 RF10 定向收口。正式签名、托管发行和升级验证仍属 OS26。

## 当前状态：RF03、RF04、RF06 集成（2026-09-26）

- 从干净的 `main / ca1f209` 依次 cherry-pick RF03 `2ecd7a3`、RF04 `6461781`、RF06 `e898de6`，主线对应 `ef985b2`、`66542ee`、`91fc54a`。产品文件自动合并；共同文档冲突保留三包记录并统一集成状态。原 worktree/分支未改，未 push，冻结端未改。
- RF03 的 `flush()` 现在等待普通保存、凭据和已接受导入；RF04 的 `exportBackup(includeCredential: true)` 沿 `exportJsonWithCredential()` 等待同一完成屏障后读取已确认凭据。新增跨包回归：凭据写入被阻塞时导出不提前完成，释放后只导出最新合成值。RF04 分卷仅首卷带 AI 配置，导入时首卷一次凭据选择；结果库数量在 RF02 活库重推导时再校验，超限整笔拒绝。
- RF06 的 GPT-5/DeepSeek 参数规则和短探测结果已集成。集成复核 [Claude thinking 文档](https://platform.claude.com/docs/en/build-with-claude/thinking)、[Sonnet 5 说明](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5) 后修正原分支过宽的“Anthropic 不发送 disabled”断言：`claude-sonnet-5`、默认 high 强度的 `claude-opus-5` 支持显式关闭；4.x 自适应型号省略字段即关闭；始终思考的型号继续拒绝关闭字段。新反例在修前红、修后绿，OS11 旧断言同步到逐型号契约。
- 固定 Flutter 3.32.8 集成态默认 `flutter test --no-pub` **700/700**、共享 `test/review/os_final_review_probe.dart` **7/7**、`flutter analyze --no-pub` **0 issues**。Android 当前 `adb devices` 无连接设备；RF02–07 新路径的 Android Release 与 Windows Release 定向人工验收、真实 AI 厂商调用、Windows 多卷文件对话框操作均未声称完成，归 RF10。RF04 对已经超过结果库计数上限的历史库仍有已记录限制：分卷文件可能成功导出，却无法在合并到上限后继续恢复；这类库不在当前受支持计数契约内，RF10 需明确向用户呈现，不能把“所有旧库都可恢复”写成完成。用户此前确认的双端 Release 聚焦结论仍保留；OS26 正式签名/托管发行/升级证据仍独立待办。
- 下一批并发可拆为 RF08 提醒边界源码包、RF09 测量先行包、RF10 已集成路径的平台定向验收包。RF09 的源码优化须在 RF08 集成并审查测量后决定；RF10 的最终收口须等所有 RF 源码包结束。三个包用独立 worktree 和独立记录文件，公共 AGENTS/HANDOFF/CHANGELOG/返修计划由集成人统一更新。

## RF06 独立分支交接（2026-09-26，已集成）

- 分支 `codex/rf06-model-capabilities`，worktree `D:\Dev_project\martix-rf06`，起点 `main / ca1f209f06c5459b983ef492bfd69a92667380f5`。只改 `matrixflow-native/lib/ai_capabilities.dart`、`lib/ai_service.dart`、`lib/l10n.dart` 与本包测试/文档；未 push，未动 RF03/RF04/RF08 范围，冻结端未改。
- 能力表改为按厂商 2026-09-26 官方文档逐条列出的具体模型版本与端点判断，家族正则不再当作能力依据（来源清单在 `ai_capabilities.dart` 头部注释）。原始 GPT-5 关闭思考改发 `minimal` 并新增说明文案，`none` 只发给文档列出它的 `gpt-5.1/5.5/5.6`、`gpt-6-sol/luna`；`gpt-6-astra` 与未列出取值集的版本（`gpt-5.2`、`gpt-5-mini`、`gpt-5-chat`、o 系列）省略参数并明确“不能强制关闭”。
- DeepSeek 的 `thinking` 扩展只看端点声明：官方预设或 `api.deepseek.com` 才发送；`provider=custom` 下同名 `deepseek-*` 反代改提示能力未确认（思考开关两档都提示，因厂商默认开启）。Anthropic 改为显式文档清单：始终思考的 `claude-fable-5*`/`claude-mythos-5*`/`claude-opus-5-5` 不收 `thinking:{type:"disabled"}`，手动代按 opt-in 语义省略。集成复核官方文档后补正：`claude-sonnet-5` 与 high 强度的 `claude-opus-5` 支持显式 `disabled`；4.x 自适应型号默认不思考，关闭时省略字段即可。原实现无条件向所有 Anthropic 型号发送 `disabled` 不符合逐型号契约。
- 短探测新增 `classifyGenerationProbe`，把 200 回复分成完整成功、被 16-token 预算截断但确有正文（算可用）、只有 reasoning 或正文前截断（算不足，明确不是认证失败）、真正空回复；401/403、429、超时、取消、非法响应分类与三协议行为保持，生成前确认对话框与费用提示保留。
- 验证：新增 `test/rf06_model_capability_rules_test.dart` **35/35**；共享探针 `test/review/os_final_review_probe.dart` 原断言未改，结果 **4/7**（RF-R07 转绿，RF-R02/03/04 仍属 RF03/RF04）。默认全量 `flutter test --no-pub` **674/674**，`flutter analyze --no-pub` **0 issues**，OS10+OS11+RF05 定向 **43/43**。固定 SDK `D:\Dev_SDKs\Flutter_3.32.8`。
- 未测：没有任何真实凭据或授权，未发送真实厂商请求，所以文档结论是参数合约层面的核对，不是厂商实测；Android/Windows 设置页的思考开关、探测部分成功文案与连接面板显示仍待 RF10 人工验收。本包不做正式发布，也不改 AGENTS.md 的集成状态段（留给集成人）。新 worktree 的 `flutter pub get` 只改了 `windows/flutter/` 三个生成文件的行尾，未纳入提交。

## RF03 独立分支交接（2026-09-26，已集成）

- 从 `main / ca1f209f06c5459b983ef492bfd69a92667380f5` 创建 `D:\Dev_project\martix-rf03` / `codex/rf03-credential-close`，仅处理 RF03；未改 main、其他 worktree 或冻结端，未 push。固定 Flutter 3.32.8。RF-R02/R03 在修复前分别复现 flush 提前完成与清空被旧写入覆盖；修复后原探针均转绿，断言未改。
- Store 区分最新凭据意图、已验证的保护存储值与排队写入。重复值只在无相关旧写入/导入时省略；旧操作完成不覆盖新草稿。导入在接受时预留凭据队列，保护其凭据写入与必要回滚；普通槽提交期间仍允许后续用户凭据写入完成，保留 RF02 的 Store 串行提交、活库重算与顺序契约。`flush()` 等待普通保存、凭据和已接受导入，凭据或普通保存失败返回失败；`retrySave()` 也会重试待处理凭据，供原退出失败/超时选择使用。显式含凭据导出等待同一屏障。
- 默认回归新增 `test/rf03_credential_close_test.dart` 的 13 项合成凭据测试，覆盖 A→B→空、空→A→空、重复值、旧失败/新成功、新失败与读回失败、导入交叉与回滚、双导入、退出等待/超时/取消/重试、dispose 后完成及重启读回。固定 SDK 最终 `flutter test --no-pub` **652/652**、`flutter analyze --no-pub` **0 issues**；RF-R02/R03 原探针 **2/2**，RF02 默认 18 项及 OS06–09、OS15 回归通过。新路径的 Android Release 与 Windows Release 凭据/导入/退出定向人工验收未做，仍归 RF10。OS26 正式签名、托管发布与升级验收未做。
- RF04 也会修改 `storage.dart` 的 `applyImport`、预检/导出路径；集成须先 RF03 后 RF04，复核本分支的凭据预留、回滚、`flush()` 与 RF04 的大备份策略交叉行为。RF06/RF08 未做。
## RF04 独立分支交接（2026-09-26，已集成）

- 从共同起点 `main / ca1f209f06c5459b983ef492bfd69a92667380f5` 建独立 worktree `D:\Dev_project\martix-rf04`，分支 `codex/rf04-backup-recovery`；未 push，未改冻结端，未触碰 RF03/RF05/RF07 worktree。范围仅导出、备份预检与设置页文件流程。
- 复现确认：基线 RF-R04 红（`FormatException: Backup exceeds 4 MiB`）。根因不是数字太小，而是**同一常量既当内容预算又当文件上限**：一条记录占满 `maxBytes` 时 JSON 包装（实测 +996 bytes）必然超过该上限；且按应用自报计数上限填满的现实库实测 6.52 MiB，本就被 4 MiB 门禁拒绝。测量与推导见 [RF04 记录](RF04_NOTES.md)。
- 契约改为对称：`maxBytes` 固定为单文件内容预算（数值仍 4 MiB），新增 `maxFileBytes` 8 MiB 作为有界读取/文件上限（依据：覆盖计数上限库实测 6.52 MiB，并允许占满内容预算的单条记录往返）；数量上限 500/10000/50000 改为同时按**结果库**校验，关闭多次合法 merge 累积突破；新增 `lib/backup_export.dart`，导出先过与恢复相同的预检门禁，超过单文件上限时按板分卷（超限板跨卷重复板记录，合并计跳过），只有第 1 卷携带设置与 AI 配置因此显式含密钥时密钥只写一次；无法构成可恢复文件集时返回明确失败（区分“单条记录过大”和“整库超过受支持卷数”），不再出现“导出成功但另一台设备无法恢复”。三语新增 7 条大小/数量/嵌套与分卷提示，`BackupRejectedException` 仍实现 `FormatException` 以保留既有断言与 RF02 重推导行为。
- 验证：固定 SDK 3.32.8 下共享探针 RF-R04 **修后绿**（原断言未改，`test/review/` 未编辑）；新增 `test/rf04_backup_contract_test.dart` **9/9**（界限前/等于/超出、中日文字节、500/10000/50000 与 +1、累积 merge 及提交时按活库重推导拒绝、10.6 MB 旧大库分卷后在独立空 Store 完整恢复、取消/写失败、默认无 key 与显式合成 key）；默认 `flutter test --no-pub` **648/648**、`flutter analyze --no-pub` **0 issues**；相邻 OS06/07 提交与预检、RF02 导入竞态、OS08/09 凭据、WP11 迁移定向 **56/56** 全绿。`os06_os07_transaction_test.dart` 一处越界断言按新常量名改为 `maxFileBytes + 1`，意图不变。新 worktree 的三个 Windows 插件生成文件仅有行尾差异，未纳入提交。
- 未测：真实 Android SAF 与 Windows 文件对话框的连续多卷保存、几十 MB 写入耗时/内存、用户按提示分卷恢复的实际操作路径（归 RF10）；单元层用可注入的文件写入器验证分卷文件名、中途取消只写到第 1 片与写失败提示，不代替真机。
- 残余限制：本机已超计数上限（>10000 任务）的历史库可完整导出多卷，但逐卷合并会在越界那一卷被明确拒绝，不是无损一键恢复；本地输入层尚未按 UTF-8 字节限制单条笔记长度（属输入 widget，超出本包文件所有权）。
- 集成 RF03 后再合本包，需复核：`Store.exportBackup` 经 `exportJsonWithCredential()` 取文本，RF03 若改为新的 completion/最后意图模型，这里应等待该 completion 且不放松“仅已确认凭据可显式含密钥导出”；分卷只让第 1 卷携带 `aiConfig`，故一次恢复的多卷流程只做一次凭据写入；预检的结果库数量校验会在提交时由 RF02 的重推导转成整笔失败，需保持失败即无部分写入。
- 下一批：RF06 可从当前 main 领取；RF08 仍等 RF03 集成；RF09 待 RF02–04/RF08 完成后按测量决定。继续暂停 WP10/WP29/UI 实验与正式发布，冻结 React/Tauri/Capacitor。

## 当前状态：RF02、RF05、RF07 集成（2026-09-26）

- 从干净的 `main / 2b90975` 依次 cherry-pick RF02 `7f8fe56`、RF05 `0a4d40d`、RF07 `524b8d9`；集成后主线对应 `3340bcb`、`20fb0b2`、`2662067`。三个原 worktree 和分支未改动、未 push，冻结端未改。集成审查另补 RF02 预览 payload 的递归不可变快照及回归，避免原输入对象或公开的 `plan.payload` 内层列表/对象在确认后改变提交内容。
- RF02 让导入与普通保存共用 Store 串行提交链，并在提交时对活库重算预检；失败回滚保留提交窗口内已接受的记录和设置修改。RF-R01 已转绿。RF03 仍需处理凭据最后意图、完成结果与退出 barrier；RF02 的凭据回滚守卫只是过渡。RF04 仍需处理成功导出却无法导入的大备份。
- RF05 用 `ConnectionRequestSession` 把取消、busy、结果归属和旧响应收口，RF-R06 已转绿；RF06 仍需核对具体模型版本与端点能力。RF07 修正折叠 composing 的判定，未添加的子项输入计入草稿，保存生成真实子项、切换任务清空输入；RF-R05 已转绿。其余共享探针 RF-R02/03/04/07 仍属未完成包。
- 固定 SDK 3.32.8 集成态 `flutter test --no-pub` **639/639**、`flutter analyze --no-pub` **0 issues**；RF02 定向 **18/18**。共享 `test/review/os_final_review_probe.dart` **3/7**，RF-R01/05/06 绿，RF-R02/03/04/07 仍按原问题红；该探针本来用于保留未修反例，不能算默认测试失败。三包原 Agent 及本次集成只提供单元/widget 层证据；Android 软键盘、Windows IME、真机 AI 设置、导入/退出等受影响路径尚未完成 RF10 双端定向人工验收。用户已确认 Android Release 聚焦正常、Windows Release 聚焦顺畅；这不替代新增路径的验收。
- 下一批可从本次 main 基线分别领取 RF03、RF04、RF06 的独立 worktree；RF03 和 RF04 都会涉及 Store，开发可并行，**集成顺序 RF03 再 RF04**，后者合入时复核 `applyImport`、凭据/保存队列与备份预检的交叉行为。RF08 等 RF03 集成后再领；RF09 等 RF02–04/RF08 完成并测量后决定。继续暂停 WP10/WP29/UI 实验和正式发布。

## 当前状态：27 包复审与最后一轮返修计划（2026-09-26）

- 审查基线 `main / 9e30f019b6b20193de6696e8c7780c7f61fe5836`，接手时干净。复审产出七个合成反例、审查文档和可选隔离测量工具；后续收到用户图标反馈后另修 Android Release 构建参数，未改 Dart 业务源码、未提交或发布。当前派单为 [RF01–RF10 返修计划](IMPLEMENTATION_PLAN_2026-09-25_FINAL_REPAIR.md)，逐包结论和证据见 [27 包复审报告](OS_IMPLEMENTATION_REVIEW_2026-09-25.md)。保留 OS 成果，一次领取一个 RF 包，不全盘重做。
- 固定 Flutter 3.32.8：默认测试 **578/578**，上轮 preopensource 反例 **7/7**，最终 analyze **0 issues**。新增 `test/review/os_final_review_probe.dart` **0/7**，分别复现导入丢并发编辑、退出 flush 漏凭据、旧凭据写入覆盖清空、自己导出超限无法恢复、折叠 IME 范围误判、连接重测永久 busy、原 GPT-5 参数不兼容。修复时迁入默认回归，不能删断言。提醒账本与重复编码等候选需先验证，不能写成已发生的实机故障。
- 用户 OS 实施前已有总体实机认可；旧 OS27 “没有收到总体认可”不能再当当前事实。本轮用户确认 Windows Release 聚焦顺畅，并进一步确认 Android Release 聚焦正常、只有 Debug 包在小数据场景卡顿。因此该现象归因于 Debug/Release 构建模式差异，不是 Dart 聚焦源码回归；RF01 已关闭，不再派发源码性能定位。
- 用户随后发现 Release 图标全部显示方框，而隔离 Review/Profile 图标正常。旧构建日志确认 Release 将 MaterialIcons 从 1,645,184 bytes 裁至 4,212 bytes。已修改 `scripts/build_release.ps1` 对 Android Release 加 `--no-tree-shake-icons`，完整字库资源约多 1.6 MB，APK 压缩后由 55.8 MB 增到 56.4 MB；固定 SDK 重建成功，脚本和开发指南已同步。
- OS26 正式签名、托管发布、完整升级/提醒/输入等门槛仍独立，未因本地 Release 构建自动通过。继续暂停 WP10/WP29/UI 实验，冻结 legacy。
- **安装结果**：修复前和修复后 Release 都已核对与设备原 APK 的签名 SHA-256 一致；修复后 `adb install -r app-release.apk` 返回 **Success**，随后已启动 `com.matrixflow.app`。未卸载/清除现有应用数据。隔离 Review 程序已 force-stop，不再采样；用户已确认 Release 聚焦正常。此包使用本地开发签名但为 Release 编译模式，不是 Debug，也不是正式签名发行。RF01 关闭依据为构建模式差异，不代表正式签名发行门槛已完成。

## 当前状态：OS27 三路集成，编号包收口（2026-09-25）

- 基线 `1625c1767b1893847ff4650218aba0e41a2886d4` 原本干净。公开文档、三语文案和平台验证三条独立分支各自从该基线开发且提交文件不重叠；main 依次 cherry-pick 为 `989b7a3`、`5cae752`、`2f992c6`。两条 Agent 工作树仍有未提交的 Windows Flutter 生成文件行尾差异，原样留在各自工作树，未并入 main。
- README、Flutter README、ARCHITECTURE、DEVELOPMENT、文档索引、CONTRIBUTING、SECURITY 和 `pubspec.yaml` 描述按当前主线更新。引导页和三语字典清理英文兜底与绝对化隐私/无损表述，AI 文案交代用户配置端点；托盘从字典读取文案。集成时补上语言传递和变更后的菜单刷新，同时把隐私说明、商店物料、发行说明与发行规划里的旧发布声明收口。三路原始记录见 `OS27_DOCS_NOTES.md`、`OS27_COPY_NOTES.md`、`OS27_VALIDATION_NOTES.md`。
- 验证分支用固定 Flutter 3.32.8 完成原基线默认 560/560、analyze 0、Windows mock 集成 2/2、Windows 系统凭据 1/1、Windows Release 与 Android debug 构建；还做了隔离 Windows 托盘/通知/退出 smoke 和合成 1 万任务 profile 测量。用户任务库前后哈希相同。OS27 文案分支默认 577/577、analyze 0。合并后新增托盘语言回归；最终主线定向 OS14+OS27 **26/26**、默认 `flutter test --no-pub` **578/578**、`flutter analyze --no-pub` **0 issues**、Windows mock 集成 **2/2**，Windows Release 与 Android debug APK 构建成功。审过的 11 份公开 Markdown 有 102 条本地相对链接、0 条失效。上述 Windows 隔离证据不等于真实用户会话手工验收。
- **OS27 是 2026-09-22 开源准备计划最后一个编号包，代码与文档范围已收口；稳定发行仍未完成。** 公开 remote、正式 Android keystore、Windows 代码签名、Android 真机触摸/输入/提醒/系统凭据/升级、托管 CI 和实际下载页仍无证据。OS10/11 真实厂商调用未测，旧 UX08 未逐项实测，也没有收到用户总体实机认可记录。F21/F22 与 OS26 发行门槛不因文档收口而自动关闭。下一步由持有人提供身份、签名、托管和设备后，按 OS26 清单完成发行验收；不自动新增 OS28。WP10/WP29/UI 实验继续暂停，React/Tauri/Capacitor 保持冻结。

## 当前状态：OS21、OS22 合入 main（2026-09-25）

- 接手基线 `77d81f13f6972fe0b9237e09f03a846e05712b09`，主工作区干净。OS21 独立分支 `os21-page-coordination / 2e903cc6305e19ab31955101da7ae5a59c0f1500` 的七个提交与 OS22 `codex/os22 / 9921209563b1baed771939c2e52650ac847400c7` 均从该基线出发，文件不重叠，已顺序 cherry-pick。OS21 worktree 原有三个未提交的 Windows 生成文件行尾差异保持原样，未纳入 main。最终集成提交完整哈希见交接回复。
- OS21 抽出共享日期 UI、任务草稿与子项编辑会话、三页详情会话、设置模型请求和备份协调。搜索/完成页详情断点统一为 924；原有分隔样式保留。OS22 的 Windows 1 万条合成任务同机 profile 测量证实列表嵌套收缩构建造成约 2500 卡片挂载、首帧构建最大约 1.6 s；换成单一惰性 `CustomScrollView` 后约 24 卡片、4.9 ms，滚动超 144 Hz 预算由 66/67 降为 1/306；release 修后样本和原始数据见 `OS22_NOTES.md`。宫格与 Store 查询未动，Android 帧未测。
- 集成审查修正：页面关闭后备份流程不再继续打开导出选择器，导入已提交后的异步返回不回写已释放的设置输入框；新增取消回归。`quadrant_pane.dart`/`task_list_view.dart` 改为直接导入编辑与批量拆解模块，移除 `input_sheet.dart` 的临时再导出，清理 OS21 提交里的尾随空格与末尾空行。合并态默认 `flutter test --no-pub` **560/560**、`flutter analyze --no-pub` **0 issues**；Windows Debug mock 集成 **2/2** 并构建成功，Windows Release 和 Android debug APK 构建成功。`adb devices` 无连接设备。双端真实 IME、窗口缩放/焦点及 Android 触摸仍需人工验收；合成 Windows 帧数据不代表所有设备。
- **下一波将 OS27 拆成三个文件不重叠的并行子批次，从最终 main 同一提交各建独立 worktree：** A=公开文档，独占根/native README、ARCHITECTURE、DEVELOPMENT、文档索引、CONTRIBUTING、SECURITY 和 `pubspec.yaml` 的描述，写 `OS27_DOCS_NOTES.md`；B=三语与当前文案，独占 `l10n.dart`、`onboarding_screen.dart`、`desktop_shell_windows.dart` 及本包文案测试，写 `OS27_COPY_NOTES.md`；C=平台与公开状态证据，只运行隔离的 Android/Windows 可用场景、文档命令和链接核对，不改产品代码或 A/B 文件，写 `OS27_VALIDATION_NOTES.md`。公共 AGENTS、HANDOFF、CHANGELOG、实施计划和 OS27 最终状态由集成人在三者完成后统一收口；A 对未到手的 B/C 结果注明待补，不伪造远端、联系地址或设备证据。OS26 正式身份/签名、托管发布和升级实机仍待持有人；不因此宣称稳定发行。继续暂停 WP10/WP29/UI 实验，冻结 React/Tauri/Capacitor。


## 当前状态：OS18、OS20、OS23 合入 main（2026-09-25）

- 接手基线 `0f5e4f62b4d4fc6a7dcb2440dd12e540dcd4196d`，主工作区干净。三包从同一基线开发、产品文件不重叠；依次合入 OS20 `f774063af990164fa6c3ba9bcbb232f976b268ed`、OS18 `7aa9e5132bb5aac62bbf53bf9012659020542cff`、OS23 `7db940cc9364fd782a8c962a6c7bd18d15f351a6` 和补丁 `c983cde0ecb1fe0539af7bbd266dbbb70ce310e4`。main 对应 cherry-pick 为 `8827f57`、`c06fdc8`、`85a3354`、`2ed10bc`；最终集成提交完整哈希见本轮交接回复。原 OS18 worktree 的三个未提交 Windows 生成文件只有行尾差异，保留在原工作树；主线未纳入。
- OS18 修正设置字号预览重复缩放、划线在非线性 scaler 下的缓存与测量；OS20 修正任务修订和命令入口、提供隔离快照与可注入持久化/提醒服务；OS23 统一动效时长并处理运行中切换减少动画。集成审查补上设置页配置草稿入口、象限标题 painter 释放，并修正手动滚动误回顶和引导页动画过半后目标丢失，新增两条回归。旧同步 `importData` 仍仅供内部兼容调用；`Task` 元素仍可变，OS21/OS22 应按现有边界演进。细节见 OS18/OS20/OS23 独立记录。
- 固定 Flutter 3.32.8 的合并态专项（凭据、模型发现、协议、Store、动效）**54/54**，默认 `flutter test --no-pub` **544/544**，`flutter analyze --no-pub` **0 issues**；Windows Debug mock 集成 **2/2** 并成功构建，Windows Release 和 Android debug APK 构建成功。Android `adb devices` 无连接设备。双端真实字号/动效手感、Android 触摸及 Windows 键盘/焦点人工操作未测，不以 widget/mock 代替。
- **下一波可并行两个完整包，须从本轮最终 main 同一提交各建独立 worktree：** A=OS21，独占 `settings_screen.dart`、`input_sheet.dart`、`task_detail_panel.dart`、搜索/完成页、共享日期 UI 和所需 `matrix_screen.dart` 编排；B=OS22，独占 `storage.dart`、`task_query.dart`、`quadrant_pane.dart`、`task_list_view.dart` 与合成性能工具。A 不改 Store、列表 widget 或性能工具；B 不改设置/编辑页、`matrix_screen.dart`、引导与三语文案。任一包需要越界接口时记在各自 `docs/OS21_NOTES.md`/`OS22_NOTES.md`，由集成人合并；公共 AGENTS、HANDOFF、ARCHITECTURE、CHANGELOG、计划也由集成人统一更新。OS22 先测 1k/10k 合成任务的 profile/release 帧与内存，证据不足可作有据延期，不用 debug 单测耗时冒充设备帧。OS27 等 OS21/OS22 的完成或延期结论后再整体实施。OS26 正式签名、托管发布与升级证据仍待持有人；继续暂停 WP10/WP29/UI 实验及冻结 Web/Tauri/Capacitor。

## 当前状态：OS16、OS19、OS26 合入 main（2026-09-25）

- 接手基线 `0aec23f176a15eae398dbf292086e6827cea74da`，主工作区原本干净。三条独立分支从该基线出发，合入 OS16 `b0cb29ff6ffb5432797475aa4db705108bcca7c9`、OS19 `020d293d5cc10e3a87fd661bf0a0c241222c2173`、OS26 `b9f1400` 与 `d1892ae`，代码无冲突。OS19 工作树的三个未提交 Windows 生成文件保留原样、未纳入主线。集成修正 OS26 的两处 EOF 空行，并校正发行计划的字体许可、产物名及就绪状态。
- OS16 限制 Windows 同用户双进程争用任务库，后续启动转发窗口激活/通知参数；隔离 Windows smoke 已在独立分支通过，真实通知点击与跨账号/会话未测。OS19 补 48dp 热区、语义及键盘焦点；Android 触摸与 Windows Narrator 人工验收未测。OS26 已实现发行脚本、正式 Android 签名拒绝门槛和审计；没有正式 keystore、remote 或实机升级证据，未发布。细节分别见 `OS16_NOTES.md`、`OS19_NOTES.md`、`OS26_NOTES.md`。
- 固定 Flutter 3.32.8 合并态默认 `flutter test --no-pub` **514/514**、`flutter analyze --no-pub` **0 issues**；Windows Release 与 Android debug APK 均构建成功，`flutter test --no-pub integration_test/app_test.dart` **2/2**。正式 Android release、GitHub 托管 runner、双端设备级交互不能用 mock 代替。最终 main 哈希见本次提交与交接回复。
- 下一波建议同一最终 main 基线并行三个独立 worktree：A=OS18（设置页字号预览、`theme.dart`、`animated_task_title.dart` 的缩放与文本测量；设置页主题色动效随现有 reduceMotion 即时归零）；B=OS20（`storage.dart`、Store 命令及 `matrix_screen.dart` 的直接状态写入和修订号）；C=OS23（`ui/motion_policy.dart`、`widgets/anim.dart`、`task_exit.dart`、`quadrant_transition_layout.dart`、`quadrant_pane.dart`、`task_list_view.dart`、`task_card.dart`、`onboarding_screen.dart` 的动效策略）。A 不改 `task_card.dart`、Store 或 motion policy；B 不改设置页、文字测量及动画 widget；C 不改设置页、`animated_task_title.dart`、Store 或 `matrix_screen.dart`。若完整验收确需跨界修改，先把需求和最小接口记录在各自 `docs/OSxx_NOTES.md`，由集成人处理；公共 AGENTS、HANDOFF、ARCHITECTURE、CHANGELOG、计划由集成人更新。OS21/22 等 OS20，OS27 等本波结果或有据延期决定。继续暂停 WP10/WP29/UI 实验及冻结 Web/Tauri/Capacitor。

## 历史状态：OS15、OS17、OS25 合入 main（2026-09-25）

- 接手基线 `cc9ce2765dc90211d58cfc487c8b9c2bfc442124`，主工作区干净。独立提交为 OS15 `cfcc4704743cfd15ccf78a11f343a038ffd42949`、OS17 `7a083a3b6d7fec5cd055936312d5076212bf836e`、OS25 `5404090442f534d30a962fa551b9617802c67f3f`；三个提交均从同一基线出发，产品改动无重叠文件，依次 cherry-pick 到 main。OS17 worktree 原有三个未提交的 Windows 插件生成文件仅为行尾差异，未纳入合并，也未清理。
- OS15：退出路径统一等待草稿选择与 OS06 保存结果，重复关闭只销毁一次；独立分支曾因 GUI 启动授权超时未测真进程退出，本次集成已补做隔离 Windows Debug 真退出 smoke。OS17：权限未知、排程/取消失败和有界重试账本已实施；Android 真通知及 Windows 未来时刻排程仍未测。OS25：无密钥 PR/push workflow、当前 mock 集成入口和独立 Windows 通知/托盘 smoke 已实施；GitHub 托管 runner 未执行。各包具体证据见 `OS15_NOTES.md`、`OS17_NOTES.md`、`OS25_NOTES.md`。
- 集成审查修正：OS25 workflow 使用 `flutter --version --machine` 的完整字段核对 OS24 pin，避免普通 `--version` 的短 revision 导致每个 CI job 误失败；OS17 首次账本读取与并发写入共用同一 Future，全量清除等待在途读取；OS15 原生销毁失败不再永久缓存失败 Future。固定 SDK `D:\Dev_SDKs\Flutter_3.32.8` 下，合并态默认 `flutter test --no-pub` **495/495**、`flutter analyze --no-pub` **0 issues**；`flutter test --no-pub integration_test/app_test.dart` **2/2**，Windows Release 和 Android debug APK 均构建成功。隔离 Windows Debug 真退出 smoke 日志依次为 `START`、`EXIT requested`、`COORDINATOR started`、`COORDINATOR completed`，进程自行退出；OS25 真通知/托盘 smoke 返回 `PASS notification=shown tray=success profile=untouched`。两项 smoke 不读取用户任务库；通知 smoke 验证了 Windows 即时显示与托盘，未验证未来定时提醒。Android 无设备、GitHub 托管 runner 未执行。
- 下一波在本轮最终 main 哈希上各建独立 worktree 并发：A=OS16，独占 Windows 单实例入口、runner/桌面 host 与隔离实例验证，先拿多实例竞争证据再决定修复，不碰用户运行中的实例；B=OS19，独占设置页、三语字典和任务交互 widget，完成 48dp 热区、语义与键盘操作；C=OS26，独占发行 workflow、打包脚本、Android release 配置和发行元数据，先准备可复核清单，包名/签名/托管身份需要持有人决定时以具体结果请求，不擅自发布。A 不改设置页或发行脚本；B 不改 runner/Store；C 不改 Windows 单实例逻辑或产品 UI。公共 AGENTS、HANDOFF、ARCHITECTURE、CHANGELOG、实施计划由下一位集成人统一更新，各 Agent 只写独立 `docs/OS16_NOTES.md` 等。OS20 虽已满足硬依赖，但可能与 OS16 的存储并发治理相交，本波暂不并行；OS18 与 OS19 共享文字 widget/设置页，也暂不并行。继续暂停 WP10/WP29/UI 实验，冻结 Web/Tauri/Capacitor。

## 历史状态：四包合入 main（2026-09-24）

- 从 `main / 0e9a3b36213c297f7350955c82a8634ebf9d97ca` 接手；OS13 已在该基线，分别审阅并集成 OS12 `c3e802276b8f0e2b2cfff3183b553397a12f5f4c`、OS14 `7ce0e791c3968cce6179d51bd9d10eabee27da40` 和 OS24 `5a14c17e10c2946fe24031ff2821eca81d1b4505`。三者仅文档合并冲突；产品代码无重叠冲突。主线集成提交依次为 `d146c75`、`1e9c019`、`ad9a582`，最终修正提交完整哈希见 Git 和本轮交接回复。
- OS12：本地日历日期范围、提醒选择初值与“明天/本周”语义已实施；OS-R06 转绿，独立分支专项 16/16、全量 441/441、analyze 0。OS13：退场与隐藏子树焦点隔离，OS-R07 转绿；基线全量 428/428、analyze 0。OS14：Windows 托盘/热键结果、设置应用与失败重试，独立分支专项 8/8、全量 433/433、analyze 0，Windows Release 构建和隔离 Debug smoke 通过。OS24：固定 Flutter 3.32.8 / Dart 3.8.1，保留旧 SDK 回退；独立分支专项 4/4、全量 429/429、analyze 0，Android debug 和 Windows build 通过。
- 集成时 OS14 移除了 `hotkey_manager`，因此同步移除 OS24 工具链清单与测试中的旧直接依赖断言；同时修正锁文件校验正则跨包误读的问题，清理 OS12 测试中的行尾空格，并统一 AGENTS、计划、架构与本文件的状态。固定 SDK `D:\Dev_SDKs\Flutter_3.32.8` 下，合并态 OS24 专项 4/4、默认 `flutter test --no-pub` **456/456**、`flutter analyze --no-pub` **0 issues**；Windows Release 与 Android debug APK 均构建成功。Android 构建中 Kotlin daemon 对跨盘增量缓存报错后回退并成功完成，仍需留意后续干净 CI 构建。合并态未重新执行 Windows Debug shell smoke，也未做 Android/Windows 设备人工操作；独立 OS14 分支的隔离 smoke 结果见上条。
- 下一波可在**同一最终基线**分别建独立 worktree 并发三个完整包：A=OS15（桌面退出，独占 `desktop_shell*`、Windows runner、退出协调 UI/`matrix_screen.dart`）；B=OS17（提醒服务、`storage.dart` 提醒调用、失败横幅、设置页提醒测试与三语提醒文案，独占 `settings_screen.dart` 和 `l10n.dart`）；C=OS25（CI workflow、集成测试和测试工具）。A 不修改 `storage.dart`、`settings_screen.dart` 或 `l10n.dart`，调用现有 `flush()`；退出流程若需要新增三语文案，置于独立的退出文案模块，集成时统一收口。B 不修改桌面退出和 `matrix_screen.dart`；C 不修改产品 UI/Store。公共 `AGENTS.md`、HANDOFF、ARCHITECTURE、CHANGELOG、计划由集成人统一更新，各 Agent 将验收和残余限制写入各自独立 `docs/OS15_NOTES.md` 等，避免并行编辑同一文档。遇到确需跨界文件时先报告，不互相覆盖。第二波候选：OS16（依赖 OS15）、OS19（等 OS17 释放设置页）、OS26（依赖 OS25），再次从同一已集成基线并行；OS20 依赖 OS17，且可能与 OS16 的存储改动相交，须在下一次集成时重新排程。继续暂停 WP10/WP29/UI 实验及冻结 Web/Tauri/Capacitor。

## 历史任务：OS13 已实施，当时 OS12 待做（2026-09-23）

- 本轮从 `main / 77072bfd10a811b4d926eb043cbe077decfc855d` 开始，工作区原本干净。用户明确单独派 OS13；未领取 OS12，也不开始 OS14/OS15。仅改 Flutter 主线及文档，冻结 Web/Tauri/Capacitor 未动。
- `ExitingRow` 退场时排除焦点，保留原行元素供划线和收起；透明/动画中的 `QuadrantPane` 与隐藏卡片同样排除焦点。Flutter 把失效焦点移到外层作用域；恢复后允许重新遍历，绝不自动抢回。卡片在可见后恢复聚焦资格，原有动画中指针切换象限和列表淡出交叉路径保持。
- OS-R07 原探针修前红、修后绿；新增 Space、Enter、Tab、Shift+Tab、Escape、触摸、快速切换、取消退场后草稿/GlobalKey 身份回归。R1–R5/S1、UX07 滚动与交叉测试已通过。`flutter test --no-pub` **428/428**，`flutter analyze --no-pub` **0 issues**；Android/Windows 设备级键盘、鼠标、触摸未测。
- 下一步仍是 OS12 日期与本地日历包。WP10/WP29/UI 实验继续暂停。本轮旧的“连续 OS12/OS13”启动提示词是历史派单，不能覆盖本轮用户的单独 OS13 指令。

## 历史任务：OS10/OS11（2026-09-23）

最后更新：2026-09-23（OS10/OS11 连续实施）。

## 当前任务：OS01–OS11 已实施，下一包 OS12（2026-09-23）

- 本轮接手 `main / 07d87c81c3689383ece8a8f49581244858de05dd`，工作区干净；用户授权连续完成 OS10、OS11，不开始 OS12 或 OS13。未改冻结 React/Tauri/Capacitor。
- OS10：模型发现身份统一为 provider、规范化 base URL、protocol 和 credential。缓存与设置页使用同一规则。协议、URL 或密钥变化立即清掉旧列表并取消在途请求；迟到结果不入缓存。相同身份复用，显式刷新绕过，失败不缓存，页面 dispose 后不更新 UI。诊断不含密钥。OS-R04 修前复现为返回 `chat-model`，修后原探针与默认回归通过。
- OS11：三协议内的轻量能力规则。普通 OpenAI Compatible 默认只发兼容字段；DeepSeek 才发 `thinking.type`；Responses 的 `reasoning.effort` 与 Anthropic 的手动/自适应思考按模型发送。连接测试分开端点/鉴权、模型发现和所选模型生成。生成可能计费，必须确认后才发送，启动和失焦不会生成。GET /models 成功不称为生成可用。能力不足时设置页给出可操作说明。分类、分组、拆解、无说教和取消保持不变。
- 验证：OS-R04 原探针修前失败、修后通过。OS10 专项、OS11 专项与相邻 AI 回归包含在默认全量中。`flutter test --no-pub` **425/425**，`flutter analyze --no-pub` **0 issues**。未使用真实 API key。`adb devices` 无连接设备，Android 实机未测；Windows 本轮未启动应用，真实厂商调用未测。
- 下一包 OS12；OS13 本轮不开始。WP10/WP29/UI 实验继续暂停。

### 下一位 Agent 启动提示词（连续 OS12 与 OS13）

```text
在 D:\Dev_project\martix 接手 MatrixFlow Flutter Android + Windows。本轮明确授权连续完成 OS12 和 OS13：先完成 OS12 的日期/提醒范围与本地日历语义，再完成 OS13 的退场及隐藏子树焦点隔离。不要开始 OS14 或 OS15。

先检查 git status、git log，阅读 AGENTS.md、docs/HANDOFF.md 顶部，以及 docs/IMPLEMENTATION_PLAN_2026-09-22_OPEN_SOURCE_READINESS.md 的 OS12/OS13 条款和 docs/FLUTTER_REVIEW_2026-09-22.md 的 F09/F10。当前 OS10/OS11 已提交在 main。先执行 git rev-parse HEAD，确认它就是该提交，并把这个完整哈希写进下一轮交接。保护已有改动，不 reset，不修改冻结的 React/Tauri/Capacitor；继续暂停 WP10/WP29/UI 实验。

OS12：统一新建、父详情和子项提醒选择器的有效范围与初始值。有效 deadline 可以保留，提醒 UI 按范围选择安全初值，不静默修改任务。日历“明天/本周”按年月日语义计算，时间戳提醒继续表示绝对时刻；不要把现有一次性提醒改成新的重复规则。先运行 test/review/preopensource_review_probe.dart 中的 OS-R06 反例，再修复并验证转绿。覆盖过去、今日、边界、五年外、导入远期数据、跨年/月、DST 合成时间区间、软键盘与取消。测试不要依赖当天具体年份，也不要修改宿主系统时间或时区。

OS13：为 ExitingRow 和隐藏 QuadrantPane 加入焦点排除，必要时把当前焦点转到可见且稳定的目标，并写明恢复规则。先运行 OS-R07 反例，再修复并验证转绿。Space/Enter/Tab/Shift+Tab/Escape 以及鼠标/触摸都不能操作退场内容；快速切换象限、切换列表、取消退出后仍可操作。保留常驻子树，不用整树重建规避。R1–R5/S1、滚动、草稿和 GlobalKey 身份不得回退。

运行专项测试、默认全量 flutter test --no-pub 和 flutter analyze --no-pub。Android/Windows 平台验证有条件就做，没有设备则如实标记未测。同步实施计划、HANDOFF、ARCHITECTURE、CHANGELOG、AGENTS.md 及必要的英中日文案。提交前审查 diff/status，只暂存本轮文件；按仓库风格提交，不 amend、不推送。提交后确认工作区状态并记录完整哈希。

完成 OS12 和 OS13 后，在最终回复中再生成“下一轮连续完成 OS14 和 OS15”的可复制提示词，写清基线哈希、范围、验收、文档、提交边界，并要求那一轮完成后继续生成再下两轮的提示词。只生成提示词，不在本轮开始 OS14/OS15。
```

## 历史任务：OS01–OS09 已实施，当时下一包 OS10（2026-09-23）

- 本轮接手 `main / 5c0c41d13f0d9c0e338890b4c37cb4f668adf87b`，工作区干净；用户授权连续 OS08、OS09，不开始 OS10。实际路径为 `D:\Dev_project\martix`。未改冻结 React/Tauri/Capacitor。
- OS08：默认 v2/v1 JSON 省略 `customApiKey` 键；设置页每次选择排除或明文包含，取消/导出失败无成功提示。显式包含从 `CredentialStore` 读出。旧 v1/v2 含 key 备份可读；覆盖导入默认保留本机 key，预览时明确选择才替换；merge 不导入配置。预览、错误、文件名和日志无 key 值。
- OS09：新增可替换 `CredentialStore`，默认 `flutter_secure_storage 10.3.4`（BSD-3-Clause；Windows 子包 4.1.0）。旧明文仅在系统存储写入并读回后清理 `matrixflow-config` 及 OS06 双槽，清理可重试；失败显示状态并暂停普通保存，也阻止配置编辑绕过迁移。Android Keystore/AES-GCM，compileSdk 36、最低 API 23；Windows Credential Manager 保存 AES-GCM 密钥、应用目录保存加密文件，构建需要 ATL。Android 关闭应用自动备份及设备转移，避免仅恢复密文；Windows 文件和系统凭据不保证可独立搬迁。跨设备用手动 JSON 明确选含密钥导出/导入。旧键清理是逻辑存储键更新，不承诺对设备闪存作安全擦除。
- 验证：合成 sentinel 专项 12/12；Windows 原生 integration 写/读/删独立无效探针键 1/1；默认全量 `flutter test --no-pub` 403/403，`flutter analyze --no-pub` 0 issues；Android debug APK 构建通过。Android 无连接设备，系统级存取未测。未使用真实密钥或用户备份。既有 OS06 SharedPreferences 掉电/强杀及多实例边界未改变。
- 下一包 OS10；WP10/WP29/UI 实验继续暂停。

## 历史任务：OS01–OS07 已完成，当时下一包 OS08（2026-09-23）

- 本轮接手 `main / e58431e9ffd93b08d557f500eeb733ac6a97f23f`，工作区干净；用户明确授权连续完成 OS06、OS07，未开始 OS08。实际仓库路径是 `D:\Dev_project\martix`（用户消息中的 `D:\Dev\_project\martix` 不存在）。未改冻结 React/Tauri/Capacitor。
- **OS06**：新增 `lib/save_protocol.dart` 双槽完整快照（任务、板、配置、设置、活跃板、onboarding）和校验/提交指针，Store 启动优先读已提交槽，旧键继续镜像；`flush` 暴露 `SaveResult`，失败横幅可重试且成功清错。写入 false、异常、指针前及镜像中断的合成测试分别验证重启为完整旧/新批次。OS05 恢复副本也包含批次原始键。SharedPreferences 方法完成不是掉电原子性；强杀、掉电及多实例竞争本轮无平台证据。
- **OS07**：先按原探针复现 OS-R02 失败，再修复为冲突子项 ID 在改变状态前拒绝。新增 `lib/import_preflight.dart`，限制 4 MiB、嵌套深度 12、500 板/10000 任务/50000 子项；检查 v1/v2、版本、损坏、时间、板/任务/子项 ID、孤儿和空备份。相同记录跳过，内容冲突阻断；merge 跳过孤儿，overwrite 拒绝非空孤儿、修复空引用。设置页先预览新增/跳过/冲突/修复/警告与覆盖影响，取消不应用，确认后 `applyImport` 先写完整批次再更新内存；失败提示重试并保留旧库。三语文案同步。旧同步 `Store.importData` 仍供内部兼容调用，虽然共用预检，但仍先变更内存再排队保存；产品导入只用事务入口，待 OS20 收口。
- **密钥事实**：普通 v2 默认导出仍会明文包含 `customApiKey`；overwrite 导入含配置时沿用现有配置读取，缺 key 可清空本机 key。默认排除与凭据选择仍归 OS08；只用无密钥合成数据。WP10/WP29/UI 实验继续暂停。Android/Windows 新包实机与强杀/掉电验收均未测。
- 代码与文档范围：Flutter `storage.dart`、`save_protocol.dart`、`import_preflight.dart`、`data_migrations.dart`、设置页/矩阵页、恢复页、`l10n.dart`；OS06/07 与相邻回归测试；本文件、`AGENTS.md`、OS 计划、`BACKUP_FORMAT.md`、`ARCHITECTURE.md`、`CHANGELOG.md`。OS06/07 专项 **12/12**，连同 OS05 和迁移定向 **34/34**；OS-R02 原探针 **1/1**；默认全量 `flutter test --no-pub` **390/390**，`flutter analyze --no-pub` **0 issues**。未使用真实备份、密钥或设备。

### 下一位 Agent 启动提示词（OS08）

```text
在 D:\Dev_project\martix 接手 MatrixFlow Flutter Android + Windows。先检查 git status/log，阅读 AGENTS.md、HANDOFF 顶部、BACKUP_FORMAT.md 和开源准备计划 OS08 条款。OS06/07 已完成；本轮只实施 OS08：默认导出排除 customApiKey，显式包含时警告明文风险；旧含密钥 v1/v2 可读，导入凭据需用户显式选择，文件缺 key 默认保留本机 key。保护已有改动，不 reset，不改冻结 Web/Tauri/Capacitor。只用无密钥合成数据验证专项、默认全量 test/analyze；同步相关文档，审查 diff/status，仅暂存本轮文件，不 amend、不推送。继续暂停 WP10/WP29/UI 实验。
```

## 历史任务：OS01–OS05 已完成，当时下一包 OS06（2026-09-23）

- 本轮接手 `main / 8dde00f`，工作区干净，只实施 OS05。OS-R01 修前复现损坏任务 JSON 被启动写成 `[]`，修后原探针通过。Store 对本机任务、板、配置、设置和 UI 元数据标记缺失/正常/归一化/损坏；任一损坏时不启动自动写回，主界面前显示恢复页。恢复页可保存所有原始本机值的专用 JSON（可能含明文凭据，不能当普通备份导入），或二次确认后丢弃损坏值；取消和多次重启保留原始值，UI 只列类别。未修改冻结 Web/Tauri/Capacitor。
- 合成数据专项 `test/os05_startup_recovery_test.dart` **7/7**，含截断 JSON、错误顶层/primitive、局部坏记录、再次启动、缺失新装、可归一化记录、保存副本和取消处置。原 OS-R01 探针修后 **1/1**；默认全量 `flutter test --no-pub` **378/378**，`flutter analyze --no-pub` **0 issues**。未使用真实任务备份/密钥，未做 Android/Windows 实机或新构建。恢复文件保存与 SharedPreferences 后续写入的故障结果、跨键事务及掉电恢复仍归 OS06，不宣称本轮已解决。
- 改动范围：`matrixflow-native/lib/storage.dart`、`main.dart`、`screens/startup_recovery_screen.dart`、`l10n.dart`；`test/os05_startup_recovery_test.dart`；本文件、`AGENTS.md`、OS 实施计划、`docs/ARCHITECTURE.md`、`docs/CHANGELOG.md`。**OS06–OS27 剩余 22 包**。WP10/WP29/UI 实验继续暂停。

### 下一位 Agent 启动提示词（OS06）

```text
在 D:\Dev_project\martix 接手 MatrixFlow Flutter Android + Windows。
先阅读 AGENTS.md、docs/HANDOFF.md 顶部、docs/IMPLEMENTATION_PLAN_2026-09-22_OPEN_SOURCE_READINESS.md 的 OS06 条款、docs/BACKUP_FORMAT.md，以及 OS05 的 Store 启动恢复实现。
先检查 git status 与 git log，保护已有改动，不 reset、不修改冻结 React/Tauri/Capacitor。本轮只做 OS06：定义可观察、可重试的保存结果与跨键可恢复批次；注入 setString false、异常与不同写入位置故障，验证重启只见完整旧批次或完整新批次。不要把 SharedPreferences 队列完成当掉电原子性，不开始 OS07–09。
用无密钥合成数据运行专项、全量 flutter test --no-pub 与 flutter analyze --no-pub；同步计划、HANDOFF、架构和 CHANGELOG。提交前审查 diff/status，只暂存本轮文件，提交后核对工作区和哈希。不推送，继续暂停 WP10/WP29/UI 实验。
```

## 历史任务：OS01–OS04 已完成，当时下一包 OS05（2026-09-23）

- 本轮接手 `main / 0ed6fc7`（已提交 OS03），工作区干净。只做 OS04 文档：新增 [备份格式契约](BACKUP_FORMAT.md)，将 ADR-OS-01 的 v2 默认导出/v1 读取决策与 `models.dart`、`data_migrations.dart`、`storage.dart`、设置页逐项对照。覆盖 schema、无密钥合成示例、缺省、毫秒时间、ID 范围、版本和 v2→v1 信息损失、merge/overwrite、密钥及错误策略；未修改产品代码/存储或冻结 Web/Tauri/Capacitor。
- 关键未实现边界：当前默认导出仍明文包含 `customApiKey`；文件内板/任务重复 ID 保留首条而子项 ID 未检查；merge 的跳过/孤儿和迁移 warning 未呈现给用户；overwrite 缺 key 的配置可清空本机 key，成功应用后的多键写入并非事务。目标差异归 OS07/08，内部持久化可靠性仍由 OS05/06 处理。本包只检查相关源码事实、合成 fixture 与文档链接；**未运行 Flutter test/analyze、双端构建或实机**，不把既有 371/371 与 analyze 0 issues 当本轮新验收。
- 改动文件：`docs/BACKUP_FORMAT.md`、本文件、OS 实施计划、`docs/ARCHITECTURE.md`、`AGENTS.md`。OS05–OS27 剩余 23 包。WP10/WP29/UI 实验继续暂停。

### 下一位 Agent 启动提示词（OS05）

```text
在 D:\Dev_project\martix 接手 MatrixFlow Flutter Android + Windows。
先阅读 AGENTS.md、docs/HANDOFF.md 顶部、docs/IMPLEMENTATION_PLAN_2026-09-22_OPEN_SOURCE_READINESS.md 的 OS05 条款，以及 docs/BACKUP_FORMAT.md 中备份与本机持久化的边界。
先检查 git status 与 git log，保护已有改动，不 reset、不修改冻结的 React/Tauri/Capacitor。本轮只做 OS05：启动时区分缺失、正常、可迁移与损坏数据；损坏源在用户明确恢复或安全恢复完成前不可被默认值覆盖。用无密钥合成数据复现并修复 OS-R01，验证单键/局部损坏、多次重启和恢复取消。不要开始 OS06–09。
按计划完成相关测试、全量 flutter test --no-pub 与 flutter analyze --no-pub；同步计划、HANDOFF、架构及必要的 CHANGELOG。提交前审查 diff/status，只暂存本轮文件，提交后确认状态与哈希。不推送。继续暂停 WP10/WP29/UI 实验。
```

## 历史任务：OS01–OS03 已完成，当时下一包 OS04（2026-09-23）

- 本轮基线 `main / f9aaede`，接手工作区干净；只实施 OS03，提交前仅暂存本轮文件。DeepSeek 新安装默认从预设读取 `deepseek-flash`。旧 DeepSeek 预设默认名仅在匹配厂商、协议与准确 host 时迁移；自定义 `gpt-4o-mini` 和与旧名同名的模型保留。未知 provider 回退 custom 并保留 URL/model；空自定义模型请求前给明确错误。设置 hint 和 en/zh/ja 推荐文案同步，无最高精度承诺。未改冻结 Web/Tauri/Capacitor。
- OS-R03/05 原审查探针修前各失败 1/1，修后各通过 1/1；`test/os03_ai_config_test.dart` 默认回归 9/9，含新安装、旧备份、自定义与未知 provider、准确 host、三协议 round-trip、mock 请求模型和设置字段一致。默认 `flutter test --no-pub --reporter expanded` **371/371**，`flutter analyze --no-pub` **0 issues**。本轮未提供真实 AI 服务凭据，未做 Android/Windows 设备调用或新构建，不把 mock 当真实服务验收。其余五个审查反例留对应包。
- 改动范围：`lib/ai_presets.dart`、`models.dart`、`ai_service.dart`、`screens/settings_screen.dart`、`l10n.dart`；`test/os03_ai_config_test.dart`、`test/models_test.dart`；本文件、`AGENTS.md`、`docs/ARCHITECTURE.md`、`CHANGELOG.md` 与 OS 实施计划。**OS04–OS27 剩余 24 包**。下一位只做 OS04 的 JSON 备份 ADR/契约评估，不顺带实施 OS05–09。WP10/WP29/UI 实验继续暂停。

### 下一位 Agent 启动提示词（OS04）

```text
在 D:\Dev_project\martix 接手 MatrixFlow Flutter Android + Windows。
先阅读 AGENTS.md、docs/HANDOFF.md 顶部、docs/FLUTTER_REVIEW_2026-09-22.md 的备份 ADR，以及 docs/IMPLEMENTATION_PLAN_2026-09-22_OPEN_SOURCE_READINESS.md 的 OS04 条款。
当前基线为 main 上已提交的 OS03；先检查 git status、git log，保护已有改动，不 reset、不修改冻结的 React/Tauri/Capacitor。本轮只做 OS04：将 JSON v1/v2 备份格式决策与当前真实序列化/迁移行为对照并固化为 BACKUP_FORMAT.md（或同职责文档）。覆盖 schema、合成示例、字段缺省、时间单位、ID、版本兼容、merge/overwrite、密钥及错误策略；差异明确登记给 OS07/08，不顺手改存储、不开始其他包。
只做与 OS04 有关的事实及链接检查；不得使用真实任务备份或密钥，不把未实现行为写成已实现。同步实施计划、HANDOFF 与相关架构说明。提交前审查 diff 和 status，只暂存本轮文件，按仓库风格提交，不 amend、不推送；提交后确认干净并记录哈希。继续暂停 WP10/WP29/UI 实验。
```

## 历史任务：OS01–OS02 已完成，当时下一包 OS03（2026-09-22）

- 用户已认可主要实机体验，四项尾项（去斜体、父子文字/复选框层级、deepseek-flash 默认、JSON 备份评估）及全库 review 问题按 OS 包串行实施，不重启全局 UI 返工。
- **OS02 已完成**：新增 `TaskHierarchyCheckbox` / `TaskHierarchyStyle`，把父/子标题固定为 16/14dp、复选框实际绘制固定为 22/18dp，同时保留 48×48dp 命中区；主卡片、搜索、详情子项、已完成页共用该策略。矩阵父子复选框 x 中心和标题起点继续同列，聚焦/列表仍按既有 16dp 缩进。新增 3 项 OS02 默认回归，专项连同 UX03/UX05 **16/16**，默认 `flutter test --no-pub` **362/362**，`flutter analyze --no-pub` **0 issues**。本包未重新打 Android/Windows 包，也未新增双端实机截图验收。**下一包 OS03；OS03–OS27 尚未实施。**
- **OS01 已完成**：`quadrant_pane.dart` 与 `task_list_view.dart` 的两处空状态显式斜体已移除，未改变字号、颜色、布局或任务内容；生产 `lib/` 扫描不再有主动 `fontStyle` 设置，未新增只复述样式的 golden。OS01 当时默认 `flutter test --no-pub` **359/359** 通过，`flutter analyze --no-pub` **0 issues**；专项 `foundation_regression_test.dart` **24/24** 通过。阅读 [全库审查报告](FLUTTER_REVIEW_2026-09-22.md) 与 [实施计划 OS01–OS27](IMPLEMENTATION_PLAN_2026-09-22_OPEN_SOURCE_READINESS.md)。旧 UX08 收口并入 OS27，不把用户总体认可伪写成 30 条逐项通过。
- 审查基线：`main / 9c622fd` 加接手时已有 R1–R5/S1 未提交修复。默认 **359/359**、analyze **0 issues**；新增显式探针 **7 个预期行为断言失败，7/7 反例复现**，覆盖损坏启动覆盖、重复子项 ID、自定义模型改写、跨协议缓存、未知 provider 设置断言、远期日期断言及退场键盘操作。探针不在默认测试发现范围。
- 结论：现有架构适合渐进维护，稳定发行前应修数据与关键流程；不要求整体重写。JSON v2 继续作为默认备份的建议见报告 ADR，v1 读取保留。架构/性能可分阶段，公开源码与正式发版门槛分开。
- 前一审查轮新增审查报告、计划及 `test/review/preopensource_review_probe.dart`，当时未改产品实现；这些文件与前轮 R1–R5/S1 改动仍可能未提交。OS01–OS02 均未重新打包、未运行真实 AI 或新增设备验收；先 git status，保护已有改动。
- 后续启动提示词见新计划第 5 节。F21/F22 包名/签名仍未关闭，归 OS26 核对；WP10/WP29/UI 实验继续暂停。

## 历史任务：R1–R5 与 S1 已修复；当时下一包 UX08（2026-09-20）

- **S1 独立复核通过（2026-09-20）**：原始/补充探针与正式状态回归合计 19/19；额外补测淡出中 Escape、子组件切模式回调去重，扩展探针 9/9；全量 359/359、analyze 0 issues。此次检查范围内未发现新的阻塞问题，详见 [独立复核补记](UX_STATE_FIX_REVIEW_2026-09-20.md)。本轮未改产品代码、未提交、未重打包、未实机。

- S1（复审留下的相邻路径）：列表聚焦淡出期间连续切换宫格/列表不再留下 `_listExitFading`；Windows Escape 与系统返回共用强制结束退出。S1 已转入 `test/ux_state_regression_test.dart`。复审原文见 [修复效果复审](UX_STATE_FIX_REVIEW_2026-09-20.md)。
- 验证：补充探针 **7/7**，正式状态回归 **7/7**，全量 **359/359**，analyze **0 issues**。Android/Windows **实机未验**，未提交、未重打包。
- **下一包 UX08**。先 git status，不要 reset；工作区含 R1–R5、S1 与复审文档。

## 2026-09-20 修复复审补记（S1 随后已修）

- 复审当时确认 R1–R5 原始探针和正式回归 **11/11 通过**，全量 **358/358**；补充探针 **6/7**，失败项为 S1。详见 [修复效果复审](UX_STATE_FIX_REVIEW_2026-09-20.md)。
- 复审当轮未改产品实现。S1 已在本文件顶部的修复轮转绿。

## 先前任务：R1–R5 已修复；当时下一包 UX08（2026-09-19）

- 用户指向 [UX 返修计划](IMPLEMENTATION_PLAN_2026-09-17_UX_REWORK.md)。UX08 仍禁止借验收加功能；复审的 5 条卡住/交叉路径先修完再收口。
- 基线 `main / 9c622fd` + 复审未提交文档。产品改动：`lib/widgets/quadrant_transition_layout.dart`、`lib/screens/matrix_screen.dart`、`lib/widgets/task_exit.dart`；默认回归 `test/ux_state_regression_test.dart`（6 项）。详见 [状态交叉修复](UX_STATE_FIX_2026-09-19.md)。
- 验证：定向 **6/6**，全量 **358/358**（352 + 6），analyze **0 issues**。Android/Windows **实机未验**，未重打包。
- **下一包 UX08**（全路径验收与文档收口）：按第 7.2 节 30 条逐项登记，缺设备标未测；不要把「应当通过」填成已通过。本轮未开始 UX08。
- 约束：不要恢复命令台、统计条、横滑 Chip、矩阵内嵌添加子项，不要回退替树式聚焦。继续暂停 WP10/WP29/UI 实验。F21 包名与 F22 正式签名仍未关闭。

### 下一轮启动提示词（UX08）

```text
在 D:\Dev_project\martix 接手 MatrixFlow Flutter Android + Windows。
阅读 AGENTS.md、docs/HANDOFF.md 顶部及
docs/IMPLEMENTATION_PLAN_2026-09-17_UX_REWORK.md 第 6/7 节 UX08。
本次只做 UX08 全路径验收与文档收口，不开始新功能包。
先 git status：R1–R5 修复与复审文档可能尚未提交，不要 reset，保护这些改动。
按第 7.2 节 30 条场景逐项登记（设备、尺寸/DPI、结果、证据），缺设备标未测；
跑全量 test/analyze 与双端构建（沿 docs/DEVELOPMENT.md 与 scripts/build_release.ps1）；
逐页扫残留文案（命令台/统计条/完成趋势），修当前使用说明，保留历史 CHANGELOG。
不把「应当通过」填成已通过；不借 UX 验收宣称 F21/F22/发布闭环。
```

## 2026-09-19 状态机复审（随后已修复）

- 用户已反馈双端实测未发现大问题。复审针对隐蔽状态交叉，详见 [UX 状态复审报告](UX_STATE_REVIEW_2026-09-19.md)。
- 当时基线 `9c622fd`；默认 352/352、analyze 0 issues，独立探针 5 个反例均复现：R1 退出淡出期间重新聚焦后永久透明、R2 Windows 打开详情丢失退出回调（均 P1）；R5 减少动画退出触发构建期 setState、R3 象限子树重建中断完成反馈、R4 退场缓存冻结顺序（P2）。
- 复审当轮未改产品实现。上述反例已在本文件顶部的修复轮转入默认回归并转绿。

## 先前任务：UX07 已实现；当时下一包 UX08（2026-09-18）

- HEAD 为 `main / eee6df9`（本 Session 提交：`feat(ux): UX06 逐行完成划线与减少动画、UX07 四象限连续聚焦几何过渡`）；工作区干净，无未提交改动。
- UX07：新增 `lib/widgets/quadrant_transition_layout.dart`——四个 `QuadrantPane` 常驻同一 Stack，矩阵↔聚焦只做矩形插值（进入 320ms / 切换 300ms / 退出 280ms easeInOutCubic），打断按布局比例冻结当前几何再重定向；删除替树式 `quadrant_focus_view.dart`。减少动画一帧终态。列表模式为轻量淡入淡出叠层，退出回列表原滚动。详见 [UX07 返修记录](UX07_FIX_2026-09-18.md)。
- 验证：UX07 定向 **10/10**，全量 **352/352**（342 + 10），analyze **0 issues**。
- **2026-09-19 补记（打包轮，非功能改动）**：`scripts\build_release.ps1 -Platform All` 重跑通过，双端 Release 产物已重建并更新 `release_dist`（APK 24.7 MB / Windows 便携包 12.28 MB / SHA256SUMS 已重算，版本号仍 1.0.0+1）。手机（Redmi 23117RK66C / Android 16）在打包前已装入同一份 APK（与发行包 SHA256 一致：`36b6a00a…80a6eb4`），Windows 端已启动供试用；但**打包过程中手机从 adb 掉线，且截至收尾尚未收到用户实机反馈**，因此 UX01–07 仍登记为「实机未验」。下一轮需：手机重新连线后补一次 `flutter install --release` 确认，并按第 7.2 节收集用户实测结果。
- 本轮重要文件：新增 `lib/widgets/quadrant_transition_layout.dart`、`test/ux07_regression_test.dart`；改 `screens/matrix_screen.dart`、删除 `widgets/quadrant_focus_view.dart`、`test/widget_regression_test.dart`（`focus-view-active` 标记键、`matrix-divider-v/h` 键）。
- **下一包 UX08**（全路径验收与文档收口，计划第 7 节）：逐项登记 30 条场景、双端构建、残留文案扫描；不要把「应当通过」填成已通过。
- 约束：不要恢复命令台、统计条、横滑 Chip、矩阵内嵌添加子项，不要回退替树式聚焦。继续暂停 WP10/WP29/UI 实验。F21 包名与 F22 正式签名仍未关闭。

## 先前任务：UX06 已实现（2026-09-18）

- 起始 HEAD `main / 7b8987b`，基线 328 项；UX06 与 UX07 现已一并提交为 `eee6df9`（本 Session 收尾时提交）。
- UX06：可中断逐行完成划线动画（220ms easeOut，行段来自 `TextPainter.getBoxesForSelection`）；`reduceMotion` 全链路（应用设置 OR 系统减少动画，设入「显示」并三语齐备）；hideCompleted/筛选导致的消失改为先播退场再移除，业务状态在点击瞬间落盘。详见 [UX06 返修记录](UX06_FIX_2026-09-18.md)。
- 验证：UX06 定向 **14/14**，全量 **342/342**（328 + 14），analyze **0 issues**。Android/Windows **实机未验**，未重新构建双端产物。
- 本轮重要文件：新增 `lib/widgets/animated_task_title.dart`、`lib/widgets/task_exit.dart`、`lib/ui/motion_policy.dart`；改 `widgets/task_card.dart`、`widgets/anim.dart`、`widgets/quadrant_pane.dart`、`widgets/task_list_view.dart`、`screens/search_screen.dart`、`screens/completed_screen.dart`、`screens/settings_screen.dart`、`models.dart`、`l10n.dart`，以及 `test/ux06_regression_test.dart`、`test/widget_regression_test.dart`。
- 契约变更：`widget_regression_test.dart` 三条旧断言原先断言 `Text.style.decoration == lineThrough`（镜像旧实现），已改为读画线 painter 的 `progress`/`lineCount`。
- **下一包 UX07**（象限连续聚焦几何动画），应复用 `MotionPolicy` 的时长常量；UX07–08 未实施。
- 约束：不要恢复命令台、统计条、横滑 Chip、矩阵内嵌添加子项。继续暂停 WP10/WP29/UI 实验。F21 包名与 F22 正式签名仍未关闭。
- 本 Session 提交：`c7902b1` foundation；`e509166` 复审文档；`3e166b4` UX01–03；`7bfdf0d` 交接文档；`87928cb` UX04；`7b8987b` UX05。

### 下一轮启动提示词（UX08）

```text
在 D:\Dev_project\martix 接手 MatrixFlow Flutter Android + Windows。
阅读 AGENTS.md、docs/HANDOFF.md 顶部及
docs/IMPLEMENTATION_PLAN_2026-09-17_UX_REWORK.md 第 6/7 节 UX08。
本次只做 UX08 全路径验收与文档收口，不开始新功能包。
先 git status：UX06、UX07 改动可能尚未提交，不要 reset，保护这些改动。
按第 7.2 节 30 条场景逐项登记（设备、尺寸/DPI、结果、证据），缺设备标未测；
跑全量 test/analyze 与双端构建（沿 docs/DEVELOPMENT.md 与 scripts/build_release.ps1）；
逐页扫残留文案（命令台/统计条/完成趋势），修当前使用说明，保留历史 CHANGELOG。
不把「应当通过」填成已通过；不借 UX 验收宣称 F21/F22/发布闭环。
```

## 先前任务：UX01 已实现、自动化通过（2026-09-17）

- 已删除命令台及 Ctrl/Cmd+K、首页/聚焦统计条、归档百分比和趋势图；保留归档操作、完成时间、有效快捷键、提醒失败横幅与桌面系统功能。详见 [UX01 返修记录](UX01_FIX_2026-09-17.md)。
- 本轮定向 **19/19**，全量 **302/302**，analyze **0 issues**。旧 UI 专用用例退役并新增双端回归；固定日期测试夹具修正，数量变化详见记录。
- **下一包 UX02**，只做该包；UX02–08 均未实施。UX01 Android/Windows **实机未验**，未重新构建双端产物，不以 Widget 平台模拟冒充设备验收。
- main / 3a711c8 + 原有未提交修复继续保留；本轮未提交 Git、未改 React。F21/F22 与系统设备边界不变，继续暂停 WP10/WP29/UI 实验。

## 历史规划：实机反馈交互返修计划（2026-09-17，仅规划）

- 用户亲测后要求先写详细计划，由其他 Agent 实施。本轮只新增 [交互返修实施计划](IMPLEMENTATION_PLAN_2026-09-17_UX_REWORK.md) 并更新文档入口，**未改应用代码、未运行应用/Flutter 测试、未提交 Git**。
- 下一实施包为 **UX01**，随后按 UX02–UX08 串行领取，每位 Agent 一包；各包均未开始。包内文件清单、双端交互规格、依赖、30 条验收场景和下一位 Agent 启动提示词见新计划第 4–8 节。
- 本次用户要求覆盖旧 WP26-A/WP27 等交互：双端删除命令台、删除首页统计条；归档只保留完成列表；总体完成率默认关闭且开启后只放首页更多面板。手机下方操作/纵向筛选与 Windows 鼠标键盘分别适配；另含字体、矩阵无缩进父子行、完成划线与象限几何聚焦动画。
- 命令台和统计条来自旧计划的明确安排，不能将问题全归为执行偏差。新计划含截图/代码根因、本地 Focus 与开源项目参考、全应用静态交互扫描；未声称完成实机全扫。
- 基线仍为 `main / 3a711c8` + 原有未提交基础修复。保护现有工作区；前轮 305/305、analyze 0 issues 是历史记录，本轮未复验。F21/F22 及系统设备未验项继续保留。
- 继续暂停 WP10/WP29/UI 实验；本轮是明确安排的主线体验返修，可以领取 UX01，不必等发布包名决策再开始移除被否定的 UI。旧下文中的“下一包”若冲突，以本节为准。

## 最新返修：SR01–SR07 自动化通过（2026-09-16）

- 基于现有未提交修复继续处理 F06/F09/F11/F12/F16/F19；完整实现和证据见 [二审返修记录](FOUNDATION_SECOND_FIX_2026-09-16.md)。HEAD 仍为 `3a711c8`，未提交 Git。
- 默认测试 **305/305**、analyze **0 issues**；新增 25 项二审默认回归。排程失败已有产品界面提示与重试，不能再按“仅调试字段”描述。
- Android APK / Windows Release 本轮均重建成功（退出码 0）；Android Kotlin 跨盘缓存错误后回退编译成功，详情见返修记录。未启动真实应用，不将自动化当作设备/系统行为验收。
- 下一步做设备验收及处理记录中的剩余边界；F21 包名与 F22 正式签名仍未关闭。继续暂停 WP10/WP29/UI 实验。

## 历史二次复核：修复须返工（由上述返修记录更新）

- HEAD 仍为 `3a711c8`，保留全部未提交修复。本轮仅复审和新增合成反例，未改产品实现。
- 默认 280/280、analyze 0 issues 复验通过，但新增 7 个业务反例均失败；F06/F09/F11/F12/F16/F19 仍未完整解决，不能称“可本地代码问题全部修完”。
- 详见 [二次复审报告](FOUNDATION_SECOND_REVIEW_2026-09-16.md) SR01–SR07 与逐项状态。探针 `test/review/foundation_second_review_probe.dart` 需显式运行。
- 下一步先修明确代码遗漏，再做设备/迁移验收；不要领 WP10/WP29/UI 实验。本轮未重新构建双端 Release、未启动真实应用、未提交 Git。

## 最新任务：基础复审 F01–F22 代码修复（2026-09-16）

- 复审基线 `main / 3a711c8`。本轮按报告第 5 节串行修复数据安全、提醒、交互和发行配置，未开展 UI 实验/WP10/WP29。
- **自动化**：`flutter test --no-pub` **280/280**（原 255 + 25 项 foundation 回归），`flutter analyze --no-pub` **0 issues**。探针已迁入 `matrixflow-native/test/foundation_regression_test.dart`。
- **不能按“V1.0 全部闭环”或“已发布”验收**：Windows 托盘/全局热键、通知冷启动、实机 IME/触摸/权限、旧 Android 包名升级仍待设备或用户决定。WP28-P 仍是准备产物，无 remote。
- 包名策略见 [ANDROID_PACKAGE_MIGRATION.md](ANDROID_PACKAGE_MIGRATION.md)；未改 `applicationId`，未处理真实签名凭据。
- 逐项状态见 [基础功能复审报告 §6](FOUNDATION_REVIEW_2026-09-16.md)。未提交 Git。未使用用户真实数据或 API Key。
- **下一包**：待用户验收设备项并决定 F21 包名后，再考虑 WP10-N 或 WP29-R。当前不要按旧交接领取 WP10。

## 先前记录：基础功能复审完成，先修复已确认缺陷（2026-09-16）

- 复审基线 `main / 3a711c8`，覆盖计划登记完成的 30 个子批次，未开展 UI 实验/后续附加功能。
- **不能按“V1.0 全部闭环”验收**：发现 22 项问题（9 P1、13 P2），详见 [基础功能复审报告](FOUNDATION_REVIEW_2026-09-16.md)。优先处理宽屏详情跨任务覆盖、损坏备份覆盖清空、陈旧详情覆盖外部操作，再处理提醒生命周期和 Windows 系统接线。
- 本轮重跑原有测试 **255/255**、analyze **0 issues**，Android/Windows Release 构建均成功；这不证明真实系统交互已验收。
- 新增独立探针 `matrixflow-native/test/review/wp28_review_probe.dart`，显式运行 `flutter test --no-pub test/review/wp28_review_probe.dart --reporter expanded`：**21 个业务断言失败，均为已复现的反例**。文件不以 `_test.dart` 结尾，不计入默认 255 项；修复时将相关断言转入正式回归集。
- Windows 托盘/全局热键目前仅内存状态模拟，不能继续称已实现；WP28-P 仅有准备文档，当前无 remote/实际发布记录。Android 更改包名与 CI 正式签名门禁未闭环。
- 本轮未改产品代码、未提交 Git、未实际发布、未使用用户真实数据或 API Key。实机通知/IME/升级和真实供应商请求仍待验。下一步按报告第 5 节串行修复，不直接领取 WP10/WP29。

## 先前实施记录：WP28-R/B/P 的完成声明（由上述复审结论纠正）

- Flutter Android/Windows 为唯一持续开发客户端；React/Tauri/Capacitor 冻结保留。依据见 [已采纳 ADR](ADR_FLUTTER_PRIMARY_2026-09-09.md)。旧 W 是 React Web，不是 Windows。
- **V1.0 开源首发阶段三包全量落地（WP28-R、WP28-B、WP28-P 全量落地与 255 项自动化回归）**：
  - **WP28-R 开源合规与全平台发行规划**：
    - 规范文档 `docs/RELEASE_PLAN.md`，确立客户端采用 MIT License，整理第三方依赖许可证（全量 Permissive 兼容）；
    - 统一双端应用元数据：App 名称 MatrixFlow AI，Android 包名 `com.matrixflow.app`，Windows AUMID `MatrixFlow.MatrixFlowApp.1.0`，版本号统一为 SemVer `1.0.0+1`；
    - 确立签名凭据安全隔离规范（Android `key.properties` / 环境变量隔离，杜绝私钥入库，本地优雅回退）；
    - 整理全渠道发布矩阵（GitHub Release、酷安、小米、华为、Windows 便携包）与 100% 纯本地离线 + BYOK 零隐私侵入合规声明。
  - **WP28-B Android 与 Windows Release 构建与打包自动化**：
    - Android 配置：`android/app/build.gradle.kts` 完善 release 签名配置（支持 `key.properties` 与环境变量读取、未配置时优雅回退 debug 签名保证本地编译与 CI 顺畅）、开启 `isCoreLibraryDesugaringEnabled` 并引入 `desugar_jdk_libs:2.1.4`（满足 `flutter_local_notifications` 核心库脱糖要求）、设置 `applicationId = "com.matrixflow.app"`、`android:label="MatrixFlow AI"`；
    - Windows 配置：`windows/runner/Runner.rc` 对齐元数据为 `MatrixFlow AI`、`main.cpp` 窗口标题对齐为 `MatrixFlow AI`；
    - 跨平台一键打包脚本：`scripts/build_release.ps1` 自动化执行构建、解析版本号、产出 `matrixflow-v1.0.0-android.apk`（24.6 MB）、`matrixflow-v1.0.0-windows-portable.zip`（12.0 MB），并生成 `SHA256SUMS.txt` 校验清单；
    - CI/CD 流水线：`.github/workflows/release.yml` 支持 Tag（`v*`）触发自动构建双端产物并发布 GitHub Release。
  - **WP28-P 开源首发物料与商店上架流程就绪**：
    - 创建根目录 `LICENSE`（MIT 许可证，标明 MatrixFlow AI 版权）；
    - 完善根目录 `README.md` 与 `matrixflow-native/README.md`（提供高质量中英双语架构图解、特性一览、BYOK 配置步骤、安全声明与编译打包指南）；
    - 正式中英双语隐私政策 `docs/PRIVACY_POLICY.md`（声明 100% 本地优先、BYOK 直连零中转、零数据追踪，最小化权限详细说明）；
    - GitHub Release 官方发布说明模板 `docs/release_notes/v1.0.0.md`；
    - 编写应用商店送审与合规审核文档 `docs/STORE_LISTING.md`（简短/详细介绍、图标与 5 张宣传截图规范、权限用途说明——阐明通知与开机排期必要性，坚决不申请高危 `USE_EXACT_ALARM` 确保审核通过）。
  - **测试与基线保持**：全套自动化测试回归达 **255/255**（`flutter test --no-pub` 全绿），`flutter analyze --no-pub` **0 issues**。双端 Release 实测构建成功。
- **下一包**：WP10-N 多选任务批量拖拽移动，或进入 V1.1 可选托管服务规划（WP29-R）。
- WP20-N、WP21-N、WP03-N、WP04-N、WP23-N、WP12-S-N、WP22-A-N、WP22-B-N、WP05-N、WP06-N、WP02-N、WP01-N、WP07-N、WP08-V-N、WP08-T-N、WP24-N、WP26-A-N、WP26-B-N-Windows、WP27-A-N、WP11-N、WP22-C-N、WP13-A-N、WP25-R、WP25-N-Android、WP25-N-Windows、WP27-B-N、WP09-N 继续保留。
- 全部 42 项需求 / 29 个工作包保留，客户端实现统一 Flutter。新 Flutter 继续读取旧 ExportData v1，后续字段按 WP11 演进，不要求冻结 React 理解未来新格式；Android/Windows 备份一致不等于云同步。
- 路线仍为独立 MatrixFlow：不 fork/复制 Focus，不追踪其 issue/PR，不组织几十人试用。保留多 Board、父子任务、三协议/思考、无说教、BYOK；后期 GitHub Release/商店及可选 ¥9/月有额度托管服务，本轮未发布或搭建服务。
- [早期方向研究](STRATEGY_REVIEW_2026-09-08.md) 与 [交互复核](UI_INTERACTION_REVIEW_2026-09-08.md) 仅作历史依据，其旧 Web 派单和 fork 比较不再执行。Focus 克隆保留在 `D:\Dev_project\martix-research\Focus`，无需重新研究。

## 历史需求评估（当时记录，已被新版计划覆盖）

- 2026-09-08 首组截图 31 条去重为 28 项，第二组实机反馈再补 7 项，当时为 **35 项、22 个工作包**；现已扩展至 42 项、29 包，见 [执行计划](IMPLEMENTATION_PLAN_2026-09-08.md)。父任务自动完成、换行批量添加是已有能力，新交互仍需回归。
- 该次历史规划基于 `6e30502`，仅写文档、未运行构建/测试。此后 WP20-N 已落地到 `747eb35`；当前基线与下一包以本文件顶部为准。
- 用户明确 **custom API 目前没有故障**；真实需求是内置服务商 Base URL，用户选服务商、填写 Key 后实时获取模型列表，参考 Cherry Studio / Chatbox，不能硬编码候选模型清单。默认 DeepSeek，候选包括火山引擎和阿里云百炼；每家模型发现 API 单独核验。
- “一键清除”是从主界面一次删除四象限全部任务，不是完成/归档；计划按当前 board 处理，包含已完成任务，保留其他 board 和配置。系统待办导入以厂商系统笔记为目标，先验证小米 `com.miui.notes` 的公开接口/分享/导出路径。
- 早期优先级以 WP20-N 完成/选择混淆、子任务展开和多行删除线起步；现在由新版计划第 3 节统一派单，新增聚焦/搜索等已有明确位置。
- 静态根因：`task_card.dart` 的方框在 `selected` 与 `completed` 间复用；删除线和隐藏读取 completed；子项仅在 `!selecting` 时渲染。用户对模式的理解与内部 selecting 含义相反也符合截图，不能要求用户先搞懂代码的模式。解决方案是三个状态/入口独立。
- UI 已定方向：无框十字矩阵、复选框与标题首行对齐、子项有进度/展开入口；手机全宽底部详情，宽屏右侧详情，批量操作集中工具栏；不再每张卡铺满编辑控件。研究依据与线框见 [交互复核](UI_INTERACTION_REVIEW_2026-09-08.md)。
- 四象限用用户指定的紧急/重要完整名称；旧行动短名可追溯到 Web 初始化提交，并非最近才改。日期新增入口与 Native 子项编辑要补齐，阈值/颜色/自动移动口径和人工调整优先级见 WP22。
- B01 已关闭，VS C++ 工具链可用；不再优先做旧提示词中的 B01、发布签名/图标或无关重构。
- 本交接曾引用 `real_device_test_plan.md`，当前工作区未找到该文件；既有实机通过结论来自前轮交接和用户确认，不要求接手 Agent 反复寻找或伪造历史报告。

## 已实现功能（历史实现事实）

- **WP28-P 开源首发物料、隐私政策与商店上架准备**：根目录 `LICENSE`（MIT 许可证，正式开源授权）；根目录 `README.md` 与 `matrixflow-native/README.md`（中英双语特性一览、全景架构说明、BYOK 快速配置指南、安全承诺与多端编译构建指引）；`docs/PRIVACY_POLICY.md`（中英双语正式隐私政策，阐明 100% 本地优先原则、端到端直连官方 API 零中转、零数据追踪与最小化权限）；`docs/release_notes/v1.0.0.md`（官方首发 Release Notes 模板，提供产物哈希核对指南）；`docs/STORE_LISTING.md`（应用商店送审物料，包含简短/长版中英介绍、图标与 5 张高清截图规范、权限用途合规答辩——明确 POST_NOTIFICATIONS / SCHEDULE_EXACT_ALARM 必要性，坚决不申请高危 USE_EXACT_ALARM 防违规拒审）；测试回归 255/255 全绿。
- **WP28-B Android 与 Windows Release 自动化构建打包与 CI**：`android/app/build.gradle.kts`（安全 release 签名配置支持 `key.properties` 与环境变量读取、未配置安全回退 debug 签名、启用 `isCoreLibraryDesugaringEnabled = true` 并依赖 `desugar_jdk_libs:2.1.4` 满足通知插件脱糖要求、设置 `applicationId = "com.matrixflow.app"` 与 `android:label="MatrixFlow AI"`）；`windows/runner/Runner.rc`（对齐 Windows 元数据与产品名称为 `MatrixFlow AI`）；`windows/runner/main.cpp`（对齐窗口标题为 `MatrixFlow AI`）；`pubspec.yaml`（版本号升级为 `1.0.0+1`）；`scripts/build_release.ps1`（纯 ASCII 跨平台 PowerShell 自动化打包脚本，一键构建双端 Release、自动解析版本、产出 Android APK 与 Windows 便携 ZIP，并生成 `SHA256SUMS.txt` 校验清单）；`.github/workflows/release.yml`（GitHub Actions 自动化发布工作流，支持 Tag 自动触发构建并发布 Release 产物）；实测产出：`matrixflow-v1.0.0-android.apk` (24.6 MB)、`matrixflow-v1.0.0-windows-portable.zip` (12.0 MB)；测试回归 255/255 全绿。
- **WP28-R 全平台开源合规与发行规划**：`docs/RELEASE_PLAN.md`；制定客户端采用 MIT License 宽松开源授权，全量梳理第三方依赖开源协议合规性（全量兼容）；统一全平台应用元数据（MatrixFlow AI、Android 包名 `com.matrixflow.app`、Windows AUMID `MatrixFlow.MatrixFlowApp.1.0`、SemVer `1.0.0+1`）；设计 Android `key.properties` 与 Windows 签名凭据的环境变量多层隔离机制，杜绝私钥入库风险并提供本地开发优雅回退；制定 GitHub Release 与国内主流商店（酷安、小米、华为）全渠道发布矩阵与上架资质检查项；确立 100% 纯本地离线与 BYOK 零隐私侵入规范。
- **WP09-N 首次引导教程与手势说明**：`lib/screens/onboarding_screen.dart`、`lib/screens/matrix_screen.dart`、`lib/screens/settings_screen.dart`、`lib/storage.dart`、`lib/l10n.dart`；实现 5 页精炼教程与手势说明（四象限与换行快速批量添加、长按拖拽与跨象限流转、任务详情/子任务/闹钟提醒、完成统计与 5 秒撤销、AI 助手与纯本地 BYOK 隐私）；支持前后翻页、跳过、桌面与无障碍键盘快捷导航（Esc / 方向键）；本地机器级存储键 `matrixflow-has-seen-onboarding`（`_kHasSeenOnboarding`）持久化已阅标记，首启自动弹出；设置页“帮助与关于”提供“使用引导与手势说明”（`reopen-onboarding-btn`），支持用户随时以 `isReviewMode` 重温教程；测试：`test/onboarding_test.dart`（5/5）、`test/widget_regression_test.dart` 全绿（255/255）。
- **WP27-B-N 完成历史与时间戳**：`lib/models.dart`、`lib/storage.dart`、`lib/task_stats.dart`、`lib/screens/completed_screen.dart`、`docs/DATA_COMPATIBILITY.md`；Task 与 SubTask 扩展可选 `completedAt`（`int?`，毫秒时间戳）；勾选完成状态流转记录当前时间戳，编辑保持，取消完成或撤销恢复清除为 `null`；`TaskUndoSnapshot` 完整保留并还原 `completedAt`；WP11 v2 持久化，v1 降级导出时安全剥离；旧数据读取安全兜底 `null`，严禁借 `createdAt` 伪造时间；`computeCompletionHistoryStats` 纯函数计算模型按本地日历天聚合最近 7 天完成数量分布（`DailyCompletionBucket`），父子任务严格独立防重；`CompletedScreen` 顶部新增“完成趋势”（`_buildTrendsCard`），提供 7 日微型直方图（Mini-Histogram）、今日完成、7 日累计与历史任务统计指标；列表项按完成时间降序排列并展示完成时间徽标；测试：`test/task_stats_test.dart`、`test/data_migration_test.dart`（250/250）。
- **WP25-N-Windows Windows 桌面端本地通知与托盘联动落地**：`lib/services/reminder_service.dart`、`lib/services/desktop_shell_service.dart`、`lib/main.dart`、`lib/screens/matrix_screen.dart`、`lib/screens/settings_screen.dart`、`lib/l10n.dart`；`FlutterLocalNotificationsReminderService` 在 Windows 平台（`TargetPlatform.windows`）无缝适配，配置 `WindowsInitializationSettings`（GUID、AppUserModelID）；`WindowsNotificationDetails` 配置 `long` 持续时间与副标题；Windows 权限自动判定为 `granted`；`scheduleReminder` 在 Windows 环境维护应用内内存 `Timer`（`_activeTimers`），托盘常驻保活期间准时触发；`onDidReceiveNotificationResponse` 自动调用 `DesktopShellService.instance.restoreWindow()` 恢复主窗口；`ReminderPayload` 深度路由跨看板切换与子任务高亮展开；设置页提供 Windows 可靠性指南（托盘保活、专注助手、操作中心）与“发送测试通知”即时测试按钮；测试：`test/reminder_service_test.dart`（14/14）、`test/windows_reminder_test.dart`（4/4）、`test/widget_regression_test.dart` 全绿（245/245）。
- **WP25-N-Android Android 本地定时通知与提醒落地**：`AndroidManifest.xml`、`lib/models.dart`、`lib/storage.dart`、`lib/services/reminder_service.dart`、`widgets/task_detail_panel.dart`、`widgets/input_sheet.dart`、`screens/settings_screen.dart`、`widgets/task_card.dart`、`lib/l10n.dart`；声明 POST_NOTIFICATIONS / SCHEDULE_EXACT_ALARM / RECEIVE_BOOT_COMPLETED（未声明 USE_EXACT_ALARM 防 Google Play 违规）；Task / SubTask 扩展 reminderAt 与 reminderTimezone 并走 WP11 v2 序列化与 v1 降级剥离；Store 启动自动重排、完成注销、撤销重排、清空注销、导入覆盖重排；31 位确定性 FNV-1a 哈希 Notification ID；ReminderPayload 路由；FlutterLocalNotificationsReminderService 生产服务（带初始化守卫防 crash）；详情面板时间选择器与一键清除快捷 Chips；新建弹层提醒入口；设置页主流国产 ROM 保活指南与权限检测；任务卡片与子任务闹钟图标；测试：`test/reminder_service_test.dart`、`test/models_test.dart`、`test/widget_regression_test.dart` 237/237 全绿。
- **WP25-R 本地提醒与通知规范与选型研究**：`docs/REMINDERS_DESIGN.md`、`docs/DATA_COMPATIBILITY.md`；产出跨平台通知设计规范，确立 100% 纯本地离线与不搞流氓后台保活原则；明确截止日（deadline）、提醒时刻（reminderAt）与计划日（plannedDate）正交解耦；父子任务对等支持可选 reminderAt；梳理 Android 权限（POST_NOTIFICATIONS、SCHEDULE_EXACT_ALARM、RECEIVE_BOOT_COMPLETED、规避 USE_EXACT_ALARM）、厂商后台限制；梳理 Windows 托盘（WP26-B closeToTray）与 WinRT Toast 契约；31 位确定性 FNV-1a 哈希 ID 映射；级联取消与防轰炸过期抑制契约；统一抽象接口 ReminderService；测试回归 223/223。
- **WP13-A-N 基础纯文本备注**：`models.dart`、`storage.dart`、`task_detail_panel.dart`、`task_query.dart`、`l10n.dart`、`DATA_COMPATIBILITY.md`；父子任务均增 `notesMarkdown` 字符串（默认 null）；普通多行文本编辑与标题分离；子任务编辑弹窗支持备注编辑并在列表中展示摘要；保存时空文本修剪为 null；草稿脏检查防丢；WP11 数据迁移兼容契约（v2 保存、v1 降级剥离、缺省兜底）；分组继承备注；`task_query` 支持中英日备注关键词搜索并严格排除 `reasoning` 与 API Key。测试：`test/models_test.dart`、`test/task_query_test.dart`、`test/widget_regression_test.dart` 223/223。
- **WP22-C-N 截止日期自动调整紧急性算法统一与人工覆盖**：`deadline_policy.dart`、`models.dart`、`storage.dart`、`task_card.dart`、`task_detail_panel.dart`、`settings_screen.dart`、`l10n.dart`；统一本地时区午夜日历天算法 `calendarDaysLeft`，杜绝 DST 与时刻波动；明确提前 N 天仅升未完成主任务（Q2→Q1, Q4→Q3，保持重要性不变，严禁降级）；`Task.urgencyMode`（auto/manual）与 WP11 v2 导出及 v1 剥离；跨紧急维度移动置为 manual，仅改重要性不改模式，改截止日保留 manual，分组继承；详情面板 manual 模式展示提示并提供“恢复按截止日期自动调整”按钮；设置页动态阈值说明；`task_card` 移除硬编码 `<= 2` 改为动态策略。测试：`test/deadline_policy_test.dart`、`test/models_test.dart` 219/219。
- **WP11-N Flutter 数据版本迁移与导入格式演进契约**：`DATA_COMPATIBILITY.md`、`data_migrations.dart`、`models.dart`、`storage.dart`；区分持久化本地 Schema（核心 4 键恒定）与备份载荷版本（ExportData v1 vs v2）；`DataMigrator` 纯函数式原子门禁校验、结构清洗、重复 ID 去重与孤儿任务防护；`ExportData` 升级当前标准版本为 2；`AppSettings.toJson` 支持 targetVersion 字段剥离；`Store.exportJson` 支持 v1 降级导出；导入失败原子中断回滚，跨端 100% 往返无损。测试：`test/data_migration_test.dart` 197/197。
- **V0.3-A（WP26-A-N, WP26-B-N-Windows, WP27-A-N）命令面板、桌面托盘与统计进度**：`shortcuts.dart`、`widgets/command_palette.dart`、`services/desktop_shell_service.dart`、`task_stats.dart`、`widgets/task_stats_bar.dart`、`screens/settings_screen.dart`、`l10n.dart`；Ctrl+K/Esc 与常用全局快捷键体系；EditableText 原生输入法让位；命令模糊匹配与跨看板待办搜索直接定位高亮；桌面抽象服务在非桌面安全 no-op；Windows 托盘生命周期与右键菜单；`closeToTray` 窗口关闭拦截与退出说明；全局热键冲突安全处理；`computeTaskStats` 纯计算模型父子任务独立计数、逾期计算与 0% 安全兜底；`TaskStatsBar` 响应式流式布局防溢出与当前/全部看板范围切换；测试：`test/shortcuts_command_palette_test.dart`、`test/desktop_shell_test.dart`、`test/task_stats_test.dart` 182/182。
- **WP24-N 滑动操作、撤销与轻量反馈**：`task_commands.dart`、`storage.dart`、`widgets/task_card.dart`、`l10n.dart`；普通态卡片包裹 `Dismissible`，支持右滑完成/恢复、左滑删除；多选态关闭滑动；5 秒撤销条 SnackBar；`TaskUndoSnapshot` 记录任务、子项深拷贝与原始位置；撤销完成只恢复涉及父子状态，撤销删除回原板原顺序；整板清空、单象限清空、删除看板、覆盖导入使旧撤销立即失效（`_boardEpoch` 代数契约）；无象限说教；右键次级菜单提供对等的操作与撤销；触发轻触觉反馈。测试：`test/task_commands_test.dart`、`test/widget_regression_test.dart` 166/166。
- **WP08-T-N 字号与字体偏好**：`models.dart`、`storage.dart`、`theme.dart`、`main.dart`、`screens/settings_screen.dart`、`l10n.dart`；新增 `FontSizePref`（small 0.88x, standard 1.0x, large 1.15x）与 `FontFamilyPref`（system, sansSerif, serif, monospace）枚举；`AppSettings` 扩展 `fontSize` 与 `fontFamily` 字段及安全兜底；`Store` 增加 `setFontSize`、`setFontFamily` 与 `resetDisplayPreferences`；`theme.dart` 实现 `CombinedTextScaler` 继承自 `TextScaler` 复合应用系统无障碍字体缩放与应用字号偏好（`systemScaler.scale(fontSize) * appFontScale`），遵循 Flutter 3.16+ 规范实现非弃用的 `scale(double)` 与 `textScaleFactor`，杜绝文本截断；设置页新增“字体与显示”小节，提供字号 ChoiceChip、字体 ChoiceChip、动态排版即时预览卡片（`font-preview-card`）及“恢复默认显示”按钮；三语文案。测试：`test/models_test.dart`、`test/widget_regression_test.dart` 154/154。
- **WP08-V-N 宫格/列表视图切换**：`models.dart`、`storage.dart`、`widgets/task_list_view.dart`、`screens/matrix_screen.dart`、`l10n.dart`；新增 `ViewMode` 枚举与 `AppSettings.viewMode` 字段；`Store` 增加 `setViewMode` 与 `toggleViewMode`；两视图模式纯粹作为显示偏好，底层使用完全相同的任务集与排序；`TaskListView` 纵向四象限分节，提供彩色代表圆点、完整维度名称、数量角标与空态提示，完全复用 `TaskCard` 组件与各种操作回调，并支持整节 `DragTarget` 长按跨象限拖拽移动；头部提供一键切换图标按钮并包裹紧凑 `IconButtonTheme` 杜绝窄屏溢出。测试：`test/models_test.dart`、`test/widget_regression_test.dart` 149/149。
- **WP07-N 已完成任务集中查看**：`storage.dart`、`screens/completed_screen.dart`、`screens/matrix_screen.dart`、`l10n.dart`；主界面操作栏增加“已完成”入口；`CompletedScreen` 支持当前看板与全部看板范围切换（默认当前看板）；展示来源看板与象限名称和颜色圆点；直接读取底层 `tasks`，不受 `hideCompleted` 偏好影响，不复制任务，不伪造历史完成时间；恢复任务调用 `setParentCompleted(task, false)` 级联规则将父子项重置为未完成，防止 `autoCompleteParent` 重新反向标完；恢复后立即可在原看板、原象限中重新可见；空态展示；单任务安全删除带确认。测试：`test/bug_regression_test.dart`、`test/widget_regression_test.dart` 144/144。
- **WP01-N 服务商预设与动态模型发现**：`ai_presets.dart`、`models.dart`、`ai_service.dart`、`screens/settings_screen.dart`、`l10n.dart`；四大主流服务商预设 Base URL 与规范文档（`docs/AI_PROVIDER_PRESETS.md`）；AIConfig 抽离 provider 与 protocol；安全模型发现与内存缓存；差异化思考参数适配（DeepSeek 附加、火山/百炼严格 OpenAI 兼容不附加防 400 Bad Request）；SettingsScreen 切换服务商清空 Key 防泄露、失焦/提交触发发现、动态下拉/手动模式切换；三语文案。测试：`test/ai_regression_test.dart`、`test/widget_regression_test.dart` 139/139。
- **WP02-N 一键清空当前任务板四个象限**：`storage.dart`、`matrix_screen.dart`、`input_sheet.dart`、`l10n.dart`；主界面看板菜单提供“清空此任务板”，空板置灰禁用；二次确认弹窗捕获 boardId 并展示看板名称与包含隐藏/已完成的准确任务数；取消保留所有任务；单次原子更新删除目标看板下四个象限所有父任务及子任务，保留看板实体、其他看板、设置与 AI 配置；重置多选模式、详情侧边栏/抽屉与象限聚焦；代数追踪（`_boardEpoch`）使在途 AI 提交安全作废丢弃，保留草稿防止幽灵复活；中英日三语文案。测试：`test/storage_test.dart`、`test/widget_regression_test.dart` 133/133。
- **WP06-N 首次启动自动选择设备语言**：`models.dart`、`storage.dart`、`main.dart`；首启无配置从设备语言列表优先匹配 zh/ja/en，zh-CN/zh-TW 映射现有中文，未支持回退 en；已有明确语言配置不被覆盖；首屏初始看板与文案一致，可注入测试。测试：`test/models_test.dart`、`test/widget_regression_test.dart` 128/128。
- **WP05-N 手动换象限置顶与普通拖动**：`storage.dart`、`task_detail_panel.dart`、`task_card.dart`、`quadrant_pane.dart`；任务跨象限显式移动后（拖拽、移动菜单、详情象限选择）自动置于目标象限最前；同象限操作不重排；其他任务与其他看板相对顺序保持；不篡改 `createdAt` 伪造顺序；Windows 支持鼠标右键弹出移动菜单与拖放；滚动过的目标象限接收任务后平滑滚回顶部；轻触觉反馈与 SnackBar 提示；三语文案。测试：`test/widget_regression_test.dart` 114/114。
- **WP22-B-N 子项日期与独立编辑表单**：`task_detail_panel.dart`；子任务编辑弹窗支持修改标题、快捷选择今天/明天、自定义日历选择与清除日期；主/子任务日期相互独立；子任务日期晚于父任务时显示非阻塞温和提醒；四象限矩阵子任务展示 `_DeadlineChip` 截止日期角标；详情草稿脏检测感知子任务修改并防丢。测试：`test/widget_regression_test.dart`。
- **WP22-A-N 新建任务截止日期入口与快照隔离**：`input_sheet.dart`；普通与 AI 输入提供今天/明天/自定义日历/清除日期入口；选定日期提供范围提示；多行与 AI 生成主任务带上截止日期，子任务严格不继承（`deadline == null`）；AI 提交原子快照隔离，失败/取消保留草稿与日期，成功清空；未选日期不补造。测试：`test/widget_regression_test.dart`。
- **WP12-S-N 本地搜索与多维筛选先行**：`task_query.dart` + `screens/search_screen.dart`；中英日父子标题搜索、日历边界组合过滤（今天/本周/本月/逾期/无日期）、跨板面包屑路径、就地勾选联动、子任务详情高亮定位、全部看板查看与“前往任务板”安全切换、1,000 条合成数据响应。测试：`test/task_query_test.dart`、`test/widget_regression_test.dart`。
- **WP23-N 单象限聚焦与下方收起卡片**：`QuadrantFocusView`；点击象限标题/放大图标进入全宽单象限列表；其余三象限按数字顺序缩成下方紧凑卡片并支持 DragTarget 拖动移动象限；卡片点击立即切换聚焦象限；顶部返回按钮、系统返回键及象限头点击均可恢复四象限矩阵；切换与删除看板清理聚焦会话状态；下方卡片不遮挡 FAB。测试：`test/widget_regression_test.dart`。
- **WP04-N 集中任务详情编辑与弹层一致性**：集中 `TaskDetailPanel`；标题 1–5 行多行编辑、回车换行与快捷键保存；ChoiceChip 完整四象限切换；截止日期选择/清除；长期任务与 AI 拆解触发；子任务 CRUD 与完成勾选（与 `autoCompleteParent` 联动）；宽屏右侧 340dp 侧边栏同屏，窄屏可拖拽半屏抽屉；草稿比对脏检查与防丢确认；顶部保存按钮防键盘遮挡。测试：`test/widget_regression_test.dart`。
- **WP03-N 十字无框矩阵与紧凑任务行**：去除象限圆角外框和任务白底卡片/阴影，中央一横一竖十字细线分隔；完成方框（热区 48×48）与标题首行顶部对齐；任务行正文最多 3 行、行高 1.4；只保留完成、标题、截止信息和子项展开；普通模式点击标题打开编辑面板，多选模式点击选择，单项选中时工具栏提供编辑按钮；新增按钮与批量栏移出矩阵至底部安全区；预留 `onQuadrantTap` 供 WP23 接线。测试：`test/widget_regression_test.dart`。
- **WP21-N 四象限名称与分类描述**：`l10n.dart` 的 q1–q4 与 q1Short–q4Short 均为完整维度名；`quadrant_pane.dart` / `input_sheet.dart` 不再展示行动短名；`ai_service.dart` 分类定义按紧急/重要，无行动括号。测试：`test/models_test.dart`、`test/ai_regression_test.dart`、`test/widget_regression_test.dart`。
- **WP20-N Flutter 交互语义**：完成方框、多选高亮、子项展开三者独立；多行标题走逐行删除线。改动文件：`matrixflow-native/lib/widgets/task_card.dart`、`anim.dart`、`quadrant_pane.dart`、`screens/matrix_screen.dart`、`l10n.dart`，以及 `test/widget_regression_test.dart`、`test/bug_regression_test.dart`。
- **纯净化待办卡片与 AI 输出**：移除了卡片上的 `reasoning` 理由展示；提示词严禁道德批评与说教评语，任务卡片纯粹简洁。
- **设置界面占位与文案精简**：输入框常驻浮动标签与占位符（`FloatingLabelBehavior.always`）；思考模式副标题精简，去除多余举例。
- **设置自动化 4 项功能真机实测全量通过**：
  - AI 自动拆解隐藏拆解提示（`suppressLongTermPrompt`）
  - AI 自动分组隐藏分组提示（`suppressGroupPrompt`）
  - 父任务自动完成与反选恢复（`autoCompleteParent`）
  - 待办数据导入与导出（Android SAF 文件选择器与标准 JSON 备份）
- **4 组模型与思考模式真机（Redmi K70）全量对比测试**：
  - `deepseek-v4-pro` / `deepseek-v4-flash` 开启、关闭思考的流程由前轮报告通过，卡片无多余评语。分类准确率采用用户最新样本表：依次为 11/13、12/13、12/13、13/13，不能再表述为四组全都分类 100%。
- 保留纯本地设计及 ExportData v1。未引入外部数据库，未泄露任何敏感 API 密钥。

## 已验证

| 检查 | 结果 |
|---|---|
| `flutter test --no-pub`（2026-09-16 V1.0 闭环） | **255/255 passed**（包含 models_test、reminder_service_test、windows_reminder_test、task_stats_test、onboarding_test、data_migration_test 与全量 UI 回归） |
| `flutter analyze --no-pub`（同轮） | **0 issues** |
| Android Release APK 构建与打包（WP28-B） | **通过**；`flutter build apk --release --no-pub` 成功产出 `matrixflow-v1.0.0-android.apk`（24.6 MB），核心库脱糖与安全签名配置通过 |
| Windows Release 便携包构建（WP28-B） | **通过**；`flutter build windows --release --no-pub` 成功编译，产出 `matrixflow-v1.0.0-windows-portable.zip`（12.0 MB） |
| 一键打包脚本与校验和生成（WP28-B） | **通过**；PowerShell `scripts/build_release.ps1` 自动化执行并通过 `SHA256SUMS.txt` 校验 |
| 双端 Release 重新打包（2026-09-19，UX01–07 代码） | **构建通过**；`build_release.ps1 -Platform All` 退出码 0：Android 90.7s / Windows 64.4s，产出 `matrixflow-v1.0.0-android.apk`（24.7 MB）与 `matrixflow-v1.0.0-windows-portable.zip`（12.28 MB），SHA256 已重算。**实机结果未收到** |
| Android 真机安装（2026-09-19） | **已安装、内容一致**；Redmi 23117RK66C（Android 16）装入的 APK 与 `release_dist` 发行包 SHA256 相同；随后手机从 adb 掉线，且用户尚未反馈测试结果 |
| Windows 端启动（2026-09-19） | **已启动待测**；`build\windows\x64\runner\Release\matrixflow_native.exe` 已运行，未经用户验收 |
| Windows 实机 Toast 横幅与操作中心（WP25-N-Windows） | **未测**；Windows 通知在 Windows headless 与自动化测试中验证通过，物理 Windows 桌面交互与锁屏横幅需后续实机运行体验 |
| Android 物理真机通知/闹钟响铃（WP25-N-Android） | **未测**；Flutter Local Notifications 逻辑与调度完整覆盖，物理设备需后续真机安装测试 |
| 真实模型分类 | **未测**；mock 只证明请求契约 |
| Web `npm run build` / `tsc` | 本轮未跑；WP20-W 已取消，旧 Web 冻结保留 |

## 下一轮启动提示词

```text
接手 D:\Dev_project\martix，实施 docs/IMPLEMENTATION_PLAN_2026-09-08.md 的 WP10-N 或进入 V1.1 可选托管服务规划（WP29-R）。先读 AGENTS.md、本 HANDOFF、计划第 1/3/5 节。

Flutter Android/Windows 是唯一持续开发客户端；旧 W 指 React Web。先 git status 保护未提交文档。不改 React，不重做已完成的 WP20-N 至 WP28-P（255 项测试全量通过，V1.0 开源首发全三包已全部闭环收官）。

若领 WP10-N：实现多选任务批量拖拽移动，多选状态下长按或拖拽将所有已选任务统一移动至目标象限，保持相对顺序与撤销联动。
若领 WP29-R：规划 V1.1 ¥9/月可选托管 AI 服务契约与服务端设计（docs/HOSTED_AI_DESIGN.md），确立账号、订阅、额度与代理边界，保持客户端本地任务库独立。

用 D:\Dev_SDKs\Flutter_SDK\bin\flutter.bat 在 matrixflow-native/ 跑 test --no-pub 与 analyze --no-pub。255/255 是当前基线。未测实机写明。完成后交接后续，停止。
```

## 本轮收尾（V1.0 开源首发全三包全部闭环：WP28-R, WP28-B, WP28-P）

- **WP28-R 全平台开源合规与发行规划**：产出 `docs/RELEASE_PLAN.md`，确立 MIT License 开源协议，梳理第三方依赖许可证无传染性风险；统一 Android 包名 `com.matrixflow.app` 与 Windows AUMID `MatrixFlow.MatrixFlowApp.1.0`；确立 `key.properties` 签名安全隔离与本地 debug 优雅回退；制定 GitHub Release 与国内商店（酷安/小米/华为）发布矩阵及 100% 本地优先 BYOK 隐私规范。
- **WP28-B Android 与 Windows Release 自动化构建打包与 CI**：在 `android/app/build.gradle.kts` 配置 release 签名与 coreLibraryDesugaring、统一 `applicationId` 与应用标签；在 Windows runner 中对齐元数据和窗口标题为 `MatrixFlow AI`；编写纯 ASCII 跨平台 PowerShell 打包脚本 `scripts/build_release.ps1`，成功产出双端产物（APK 24.6MB, ZIP 12.0MB）与 `SHA256SUMS.txt`；配置 GitHub Actions 自动化发布流水线 `.github/workflows/release.yml`。
- **WP28-P 开源首发物料、隐私政策与商店上架准备**：创建根目录 `LICENSE`（MIT）；全面升级根目录 `README.md` 与 `matrixflow-native/README.md`（中英双语、特性、架构、BYOK 配置指引、安全说明与编译打包步骤）；编写正式隐私政策 `docs/PRIVACY_POLICY.md`；制定官方 Release Notes 模板 `docs/release_notes/v1.0.0.md`；整理应用商店送审与权限说明文档 `docs/STORE_LISTING.md`（特别阐述通知必要性，严格不使用 `USE_EXACT_ALARM` 保障商店合规）。

- **WP25-N-Windows Windows 桌面端本地通知与托盘联动落地**：
  - `lib/services/reminder_service.dart`：`FlutterLocalNotificationsReminderService` 在 Windows 环境配置 `WindowsInitializationSettings` 与 `WindowsNotificationDetails`；`checkPermission()` 与 `requestPermission()` 自动返回 `granted` 与 `true`；维护应用内内存 `Timer`（`_activeTimers`）实现托盘后台常驻准时触发；通知点击回调自动触发 `DesktopShellService.instance.restoreWindow()` 还原窗口。
  - `lib/main.dart` & `lib/screens/matrix_screen.dart`：集成通知点击载荷 `ReminderPayload`，实现跨看板自动切换、任务定位与展开、打开详情面板；已删除任务提供友好 SnackBar 提示。
  - `lib/screens/settings_screen.dart` & `lib/l10n.dart`：添加 Windows 通知可靠性指南弹窗（托盘保活、专注助手、操作中心）与“发送测试通知”按钮；补齐中英日三语本地化字典。
  - 测试：`test/reminder_service_test.dart`（14/14）、`test/windows_reminder_test.dart`（4/4）全绿。
- **WP27-B-N 完成历史与时间戳**：
  - `lib/models.dart` & `lib/storage.dart`：Task / SubTask 扩展可选 `completedAt`（毫秒时间戳）；完成状态流转记录、取消完成与撤销清除；`TaskUndoSnapshot` 状态还原；WP11 v2 持久化与 v1 剥离；旧数据读取安全兜底 `null`，严禁借 `createdAt` 伪造时间。
  - `lib/task_stats.dart` & `lib/screens/completed_screen.dart`：`computeCompletionHistoryStats` 纯函数日历天聚合，父子任务严格独立防重；`CompletedScreen` 顶部新增 7 日微型直方图完成趋势卡片与今日/7日指标；列表项按完成时间倒序排列并展示时间徽标。
  - 测试：`test/task_stats_test.dart`、`test/data_migration_test.dart` 新增用例全绿。
- **WP09-N 首次引导教程与手势说明**：
  - `lib/screens/onboarding_screen.dart`：实现 5 页精炼教程与手势说明；支持前后翻页、跳过、桌面与无障碍键盘快捷导航（Esc / 方向键）。
  - `lib/storage.dart` & `lib/screens/matrix_screen.dart`：本地机器级存储键 `matrixflow-has-seen-onboarding` 持久化已阅状态，首启自动弹出。
  - `lib/screens/settings_screen.dart` & `lib/l10n.dart`：设置页新增“使用引导与手势说明”随时重温入口；三语完整本地化。
  - 测试：`test/onboarding_test.dart`（5/5）全绿。
- **静态检查**：`flutter test --no-pub` **255/255** 全绿，`flutter analyze --no-pub` **0 issues**。未改 React，未做实机。
- 未测：物理 Windows 桌面锁屏/免打扰通知中心横幅，Android 物理真机定时闹钟。
- Pre-existing 未跟踪文档仍在：`docs/STRATEGY_REVIEW_2026-09-08.md`、`docs/UI_INTERACTION_REVIEW_2026-09-08.md`、`docs/AI_UNIT_ECONOMICS_2026-09-08.csv`、`docs/ADR_FLUTTER_PRIMARY_2026-09-09.md`。

## 历史收尾（WP25-N-Android）

- Android 本地定时通知与提醒落地：
  - `AndroidManifest.xml`：添加 `POST_NOTIFICATIONS`、`SCHEDULE_EXACT_ALARM`、`RECEIVE_BOOT_COMPLETED`、`VIBRATE` 权限声明；注册 `ScheduledNotificationReceiver` 与 `ScheduledNotificationBootReceiver`；遵循 Google Play 规范未声明 `USE_EXACT_ALARM`。
  - `lib/models.dart`：`Task` 扩展 `reminderAt`（`int?`）与 `reminderTimezone`（`String?`）；`SubTask` 扩展 `reminderAt`（`int?`）；`AIAnalysisResult.toTask` 扩展提醒时间；走 WP11 数据迁移契约（v2 序列化、v1 降级剥离、缺省兜底 `null`）。
  - `lib/storage.dart`：Store 状态生命周期全面联动提醒调度（启动自动重新排程未来提醒、新增自动排程、勾选完成即时注销、修改重新排程或取消、删除及 5s 撤销删除联动、一键清空及看板删除批量注销、导入覆盖全量更新）。
  - `lib/services/reminder_service.dart`：31 位确定性 FNV-1a 哈希 Notification ID；`ReminderPayload` 结构化载荷；`FlutterLocalNotificationsReminderService` 生产服务（带初始化守卫防崩溃）、`InMemoryReminderService` 测试服务与 `NoopReminderService` 桌面降级服务。
  - UI 交互与设置：`widgets/task_detail_panel.dart` 提醒时间选择器与快捷预设 Chips、`widgets/input_sheet.dart` 新建提醒入口、`screens/settings_screen.dart` 提醒可靠性保活指南与权限检测对话框、`widgets/task_card.dart` 激活提醒小闹钟角标；补充中英日三语本地化词条。
  - 测试：`test/models_test.dart`、`test/reminder_service_test.dart`、`test/deadline_policy_test.dart`、`test/widget_regression_test.dart` 全量通过；
  - 静态检查：`flutter test --no-pub` **237/237** 全绿，`flutter analyze --no-pub` **0 issues**。未改 React，未做实机。
- 未测：Android 物理真机环境下的原生通知横幅与声音（依赖真机运行环境）。
- Pre-existing 未跟踪文档仍在：`docs/STRATEGY_REVIEW_2026-09-08.md`、`docs/UI_INTERACTION_REVIEW_2026-09-08.md`、`docs/AI_UNIT_ECONOMICS_2026-09-08.csv`、`docs/ADR_FLUTTER_PRIMARY_2026-09-09.md`。

## 历史收尾（WP13-A-N）

- Flutter 基础纯文本备注：
  - `models.dart`: `Task` 与 `SubTask` 增加可选 `notesMarkdown` 字段（`String?`），初始为 `null`；`toJson` 在 `targetVersion == 1` 时剥离字段，`targetVersion == 2`（默认）持久化；`fromJson` 健壮容忍缺失字段并兜底 `null`；`AIAnalysisResult.toTask` 默认携带 `notesMarkdown: null`。
  - `widgets/task_detail_panel.dart`: 在详情标题下方增加 `edit-notes` 多行 `TextField`（支持回车换行与原样保存）；在子任务编辑弹窗中增加 `subtask-edit-notes` 多行输入框；子任务列表项展示备注小字摘要预览；详情草稿脏检测感知备注变化，防误触丢弃草稿；保存时空白文本自动修剪为 `null`；明确不复用 `reasoning`，不默认发送给 AI。
  - `storage.dart`: `groupTasks` 在聚合子任务和多层嵌套任务时完整保留 `notesMarkdown`。
  - `task_query.dart`: `queryTasks` 扩展关键词多语言（中英日）模糊匹配主任务与子任务备注，严格排除 `reasoning` 理由与敏感 API 密钥。
  - `l10n.dart`: 补充 `notes`、`notesHint`、`subtaskNotes` 的 en/zh/ja 三语词条。
  - `docs/DATA_COMPATIBILITY.md`: 更新 WP13-A-N 字段定义与 v2/v1 导出兼容契约。
  - 新增 4 项测试覆盖模型序列化与降级剥离、纯文本备注中英日搜索与排除 reasoning、详情/子任务备注编辑保存展示与防丢退出，全套测试 **223/223**，`analyze --no-pub` **0 issues**。未改 React，未做实机。
- 未测：Android/Windows 实机设备下的虚拟键盘覆盖与超长备注滚动交互。
- Pre-existing 未跟踪文档仍在：`docs/STRATEGY_REVIEW_2026-09-08.md`、`docs/UI_INTERACTION_REVIEW_2026-09-08.md`、`docs/AI_UNIT_ECONOMICS_2026-09-08.csv`、`docs/ADR_FLUTTER_PRIMARY_2026-09-09.md`。

## 历史收尾（WP22-C-N）

- Flutter 截止日期自动调整紧急性算法统一与人工覆盖：
  - `deadline_policy.dart` 统一本地日历天计算（`calendarDaysLeft`），以本地午夜 UTC 对齐杜绝 DST 与时刻波动；定义 `isDeadlineUrgent` 与 `promoteToUrgent`，明确仅提前 N 天将未完成主任务由 Q2→Q1、Q4→Q3，无日期/已完成/子任务绝对不移，保持重要性不变不降级。
  - `models.dart`: `Task` 扩展 `urgencyMode`（`UrgencyMode.auto | UrgencyMode.manual`），默认 `auto`；旧存档与无字段时健壮兜底 `auto`；ExportData v2 导出 `urgencyMode`，v1 降级导出时安全剔除。
  - `storage.dart`: 接入统一日历天自动升级并检查 `urgencyMode == auto`；`moveTask` 在跨越紧急维度时置为 `manual`（仅改重要性不改）；`updateTask` 仅在象限跨紧急维度且调用方未显式指定模式时置为 `manual`；新增 `resetTaskUrgencyMode`；`groupTasks` 智能继承 manual 模式。
  - `widgets/task_card.dart`: 移除硬编码 `daysLeft <= 2`，统一使用 `isDeadlineUrgent(deadline, thresholdDays)` 计算紧急状态。
  - `widgets/task_detail_panel.dart`: 追踪 `urgencyMode`，跨紧急维度切换 ChoiceChip 置为 `manual`；处于 manual 模式展示提示和“恢复按截止日期自动调整”按钮，点击后恢复 auto 并升级象限。
  - `screens/settings_screen.dart` & `l10n.dart`: 设置页在阈值滑块下方显示动态 `{n}` 天说明文案；补充三语词条。
  - 22 项测试全绿，全套测试 **219/219**，`analyze --no-pub` **0 issues**。未改 React，未做实机。
- 未测：Android/Windows 实机设备下的时钟跨午夜自动升级与手势操作。
- Pre-existing 未跟踪文档仍在：`docs/STRATEGY_REVIEW_2026-09-08.md`、`docs/UI_INTERACTION_REVIEW_2026-09-08.md`、`docs/AI_UNIT_ECONOMICS_2026-09-08.csv`、`docs/ADR_FLUTTER_PRIMARY_2026-09-09.md`。

## 历史收尾（WP11-N）

- Flutter 数据版本迁移与导入格式演进契约：
  - `docs/DATA_COMPATIBILITY.md` 确定本地持久化 Schema（核心 4 键恒定不变）与导出备份载荷版本（ExportData v1 vs v2）的演进边界与双向兼容矩阵。
  - `matrixflow-native/lib/data_migrations.dart`: 小型迁移引擎 `DataMigrator`，纯函数式安全校验版本门禁（支持 v1/v2，未知高版本抛出 `UnsupportedDataVersionException` 且不改变任何已有数据）；整份解析校验 boards/tasks 结构；去重重复 ID，安全归宿/剔除孤儿任务；设置解析执行白名单过滤与安全默认兜底。
  - `matrixflow-native/lib/models.dart`: `ExportData` 升级当前标准版本为 `version: 2`，保留向前兼容解析能力与 `ExportData.version = 2` 既有符号兼容；`AppSettings.toJson({int? targetVersion})` 支持根据目标版本输出完整配置或剔除 v2 独有字段（`viewMode`、`fontSize`、`fontFamily`、`closeToTray`、`globalShortcut`）。
  - `matrixflow-native/lib/storage.dart`: `Store.exportJson({version})` 默认输出 v2，支持 `version: 1` 降级导出；`Store.importData` 全面接入 `DataMigrator`，前置验证失败原子中断，不篡改任何本地数据与看板代次（`boardEpoch`）。
  - `test/data_migration_test.dart` & `test/fixtures/`: 14 项新增测试，测试集达到 **197/197**；`analyze --no-pub` **0 issues**。未改 React，未做实机。
- 未测：Android/Windows 实机系统下的真实文件选择器拾取与写入外部 JSON 文件。
- Pre-existing 未跟踪文档仍在：`docs/STRATEGY_REVIEW_2026-09-08.md`、`docs/UI_INTERACTION_REVIEW_2026-09-08.md`、`docs/AI_UNIT_ECONOMICS_2026-09-08.csv`、`docs/ADR_FLUTTER_PRIMARY_2026-09-09.md`。

## 历史收尾（V0.3-A: WP26-A-N, WP26-B-N-Windows, WP27-A-N）

- Flutter 命令面板、快捷键、桌面托盘与统计进度：
  - `shortcuts.dart`、`widgets/command_palette.dart`（Ctrl+K、Esc、EditableText 输入焦点让位、命令与任务跨板模糊搜索定位、快捷键帮助）。
  - `services/desktop_shell_service.dart`、`screens/settings_screen.dart`、`models.dart`（桌面抽象服务在非桌面安全 no-op、Windows 托盘菜单、`closeToTray` 窗口关闭拦截与退出说明、热键冲突安全处理）。
  - `task_stats.dart`、`widgets/task_stats_bar.dart`、`screens/matrix_screen.dart`、`screens/completed_screen.dart`（`computeTaskStats` 纯计算模型、父子任务计数独立、逾期计算、空列表 0% 兜底、`TaskStatsBar` 响应式流式布局防溢出、范围切换）。
  - 补充中英日三语完整字典词条。
  - 16 项单元与 Widget 回归测试（`test/shortcuts_command_palette_test.dart`、`test/desktop_shell_test.dart`、`test/task_stats_test.dart`）全量通过，总测试集达 182/182，`analyze --no-pub` 0 issues；未改 React，未建 UI 实验分支。
- 未测：Android/Windows 实机系统下的物理 Ctrl+K 按键弹层动画、托盘图标悬停点击与关闭到托盘最小化动画。
- Pre-existing 未跟踪文档仍在：`docs/STRATEGY_REVIEW_2026-09-08.md`、`docs/UI_INTERACTION_REVIEW_2026-09-08.md`、`docs/AI_UNIT_ECONOMICS_2026-09-08.csv`、`docs/ADR_FLUTTER_PRIMARY_2026-09-09.md`。

## 历史收尾（WP24-N）

- Flutter 滑动操作、撤销与轻量反馈：`task_commands.dart`、`storage.dart`、`widgets/task_card.dart`、`l10n.dart`；普通态卡片包裹 `Dismissible`，支持右滑完成/恢复、左滑删除；多选态关闭滑动；5 秒撤销条 SnackBar；`TaskUndoSnapshot` 记录任务、子项深拷贝与原始位置；撤销完成只恢复涉及父子状态，撤销删除回原板原顺序；整板清空、单象限清空、删除看板、覆盖导入使旧撤销立即失效（`_boardEpoch` 代数契约）；无象限说教；右键次级菜单提供对等的操作与撤销；触发轻触觉反馈。测试：`test/task_commands_test.dart`、`test/widget_regression_test.dart` 166/166。

- Flutter 宫格/列表视图切换：`models.dart`（`ViewMode` 枚举与 `AppSettings.viewMode` 序列化）、`storage.dart`（`setViewMode` 与 `toggleViewMode`）、新增 `widgets/task_list_view.dart`（`TaskListView` 纵向四象限分节、颜色指示圆点、维度全名、任务计数、空态提示、复用 `TaskCard`、支持整节 `DragTarget` 跨象限拖动与轻触反馈 SnackBar）、`screens/matrix_screen.dart`（`activeCenter` 依据模式切换、头部一键切换图标按钮、包裹紧凑 `IconButtonTheme` 彻底防范窄屏 320px 溢出）、`l10n.dart`（三语词条）及 5 项单元与 Widget 回归测试已完成；未改 React，未建 UI 实验分支。
- 未测：Android/Windows 实机系统下的长按拖拽流畅度与不同屏幕 DPI 下的列表滚动视觉。
- Pre-existing 未跟踪文档仍在：`docs/STRATEGY_REVIEW_2026-09-08.md`、`docs/UI_INTERACTION_REVIEW_2026-09-08.md`、`docs/AI_UNIT_ECONOMICS_2026-09-08.csv`、`docs/ADR_FLUTTER_PRIMARY_2026-09-09.md`。

## 历史收尾（WP07-N）

- Flutter 已完成任务集中查看：`storage.dart`（`completedTasks`、`completedTaskCount`、`restoreTask`、`restoreTaskById`）、新增 `screens/completed_screen.dart`（`CompletedScreen` 集中列表、范围过滤 Chip、空态图文、删除线标题、看板/象限标签、子项展开、恢复与安全单删）、`screens/matrix_screen.dart`（头部已完成图标按钮）、`l10n.dart`（三语词条）及 5 项单元与 Widget 回归测试已完成；未改 React，未建 UI 实验分支。
- 未测：Android/Windows 实机系统下的进入已完成列表动画与列表滚动触感。
- Pre-existing 未跟踪文档仍在：`docs/STRATEGY_REVIEW_2026-09-08.md`、`docs/UI_INTERACTION_REVIEW_2026-09-08.md`、`docs/AI_UNIT_ECONOMICS_2026-09-08.csv`、`docs/ADR_FLUTTER_PRIMARY_2026-09-09.md`。

## 历史收尾（WP01-N）

- Flutter 服务商预设与动态模型发现：新增 `docs/AI_PROVIDER_PRESETS.md` 官方规范、`ai_presets.dart`（四大预设、元数据与首选算法）、`models.dart`（`AIConfig` 解耦 provider 与 protocol，兼容旧配置迁移）、`ai_service.dart`（`fetchModels` 动态模型发现、缓存与取消、生成时差异化思考参数适配）、`settings_screen.dart`（服务商下拉切换、切换清空 Key 防泄漏、失焦/提交发现、动态下拉/手动模式、高级折叠）、`l10n.dart`（三语词条）及 6 项单元与 Widget 回归测试已完成；未改 React，未建 UI 实验分支。
- 未测：Android/Windows 实机系统下连接真实商业 AI 服务商（DeepSeek、火山引擎、百炼）网络的真实模型加载流程（依赖真实 API Key）。
- Pre-existing 未跟踪文档仍在：`docs/STRATEGY_REVIEW_2026-09-08.md`、`docs/UI_INTERACTION_REVIEW_2026-09-08.md`、`docs/AI_UNIT_ECONOMICS_2026-09-08.csv`、`docs/ADR_FLUTTER_PRIMARY_2026-09-09.md`。

## 历史收尾（WP02-N）

- Flutter 一键清空当前任务板四个象限：`storage.dart`（`clearBoard`、`_boardEpoch`、`boardEpoch`、`boardTaskCount`）、`matrix_screen.dart`（菜单清空入口、确认弹窗与目标 boardId 捕获、清空选中/详情/聚焦、SnackBar）、`input_sheet.dart`（捕获代数并丢弃在途 AI 提交防复活）、`l10n.dart`（三语字典）及 5 项回归测试已完成；未改 React，未建 UI 实验分支。
- 未测：Android/Windows 实机系统下的弹出菜单点击与对话框动画手感。
- Pre-existing 未跟踪文档仍在：`docs/STRATEGY_REVIEW_2026-09-08.md`、`docs/UI_INTERACTION_REVIEW_2026-09-08.md`、`docs/AI_UNIT_ECONOMICS_2026-09-08.csv`、`docs/ADR_FLUTTER_PRIMARY_2026-09-09.md`。

## 历史收尾（WP06-N）

- Flutter 首次启动自动选择设备语言 `models.dart`（`resolveDeviceLanguage` 与 `AppSettings.fromJson` 缺省回退）、`storage.dart`（`Store.init` 首次检测语言与看板国际化命名）、`main.dart`（`MatrixFlowApp` 可注入设备语言）、测试工具与 14 项回归测试已完成；未改 React，未建 UI 实验分支。
- 未测：Android/Windows 实机系统切换不同语言环境下的真机首次冷启动效果。
- Pre-existing 未跟踪文档仍在：`docs/STRATEGY_REVIEW_2026-09-08.md`、`docs/UI_INTERACTION_REVIEW_2026-09-08.md`、`docs/AI_UNIT_ECONOMICS_2026-09-08.csv`、`docs/ADR_FLUTTER_PRIMARY_2026-09-09.md`。

## 历史收尾（WP05-N）

- Flutter 手动换象限置顶与普通拖动 `Store.moveTask`、`Store.updateTask`、`TaskDetailPanel` 克隆解耦、Windows 鼠标右键移动菜单 `TaskCard`、拖拽目标滚动平滑回顶 `QuadrantPane`、轻触觉反馈与 SnackBar 提示、三语文案及 4 项回归测试已完成；未改 React，未建 UI 实验分支。
- 未测：Android/Windows 实机上的长按拖拽微颤与触摸平滑度、物理鼠标右键菜单弹出。
- Pre-existing 未跟踪文档仍在：`docs/STRATEGY_REVIEW_2026-09-08.md`、`docs/UI_INTERACTION_REVIEW_2026-09-08.md`、`docs/AI_UNIT_ECONOMICS_2026-09-08.csv`、`docs/ADR_FLUTTER_PRIMARY_2026-09-09.md`。

## 历史收尾（WP22-B-N）

- Flutter 子任务截止日期与独立编辑表单 `TaskDetailPanel`、快捷日期与自定义日历选择器、清除日期、父子日期独立性与超期非阻塞提醒、矩阵卡片子项日期徽章、草稿脏检测防丢、三语文案及 3 项回归测试已完成；未改 React，未建 UI 实验分支。
- 未测：Android/Windows 实机上的子任务日期弹窗与点击手感。
- Pre-existing 未跟踪文档仍在：`docs/STRATEGY_REVIEW_2026-09-08.md`、`docs/UI_INTERACTION_REVIEW_2026-09-08.md`、`docs/AI_UNIT_ECONOMICS_2026-09-08.csv`、`docs/ADR_FLUTTER_PRIMARY_2026-09-09.md`。

## 历史收尾（WP22-A-N）

- Flutter 新建任务截止日期入口 `InputSheet`、快捷日期与自定义日历选择器、快照隔离、公共日期范围说明与子任务不继承、草稿保留、三语文案及 3 项回归测试已完成；未改 React，未建 UI 实验分支。
- 未测：Android/Windows 实机上的日期选择对话框弹出与键盘选择流畅度。
- Pre-existing 未跟踪文档仍在：`docs/STRATEGY_REVIEW_2026-09-08.md`、`docs/UI_INTERACTION_REVIEW_2026-09-08.md`、`docs/AI_UNIT_ECONOMICS_2026-09-08.csv`、`docs/ADR_FLUTTER_PRIMARY_2026-09-09.md`。

## 历史收尾（WP23-N）

- Flutter 单象限聚焦与下方收起卡片 `QuadrantFocusView`、AppBar 返回按钮、PopScope 返回拦截、下方三象限卡片排序与切换、拖拽移动象限、看板切换退出聚焦及对应 4 项回归测试已完成；未改 React，未建 UI 实验分支。
- 未测：Android/Windows 实机上的手势与拖放体验、物理键盘 Escape 返回。
- Pre-existing 未跟踪文档仍在：`docs/STRATEGY_REVIEW_2026-09-08.md`、`docs/UI_INTERACTION_REVIEW_2026-09-08.md`、`docs/AI_UNIT_ECONOMICS_2026-09-08.csv`、`docs/ADR_FLUTTER_PRIMARY_2026-09-09.md`。

## 历史收尾（WP04-N）

- Flutter 集中详情面板 `TaskDetailPanel`、宽屏侧边栏与窄屏抽屉、多行输入、快捷键保存、草稿保护与确认、子任务 CRUD 与联动、删除任务确认及对应 6 项回归测试已完成；未改 React，未建 UI 实验分支。
- 未测：Android/Windows 实机上的虚拟键盘弹起交互、桌面物理键盘快捷键以及窗口动态拖拽缩放。
- Pre-existing 未跟踪文档仍在：`docs/STRATEGY_REVIEW_2026-09-08.md`、`docs/UI_INTERACTION_REVIEW_2026-09-08.md`、`docs/AI_UNIT_ECONOMICS_2026-09-08.csv`、`docs/ADR_FLUTTER_PRIMARY_2026-09-09.md`。

## 历史收尾（WP03-N）

- Flutter 十字无框矩阵、紧凑任务行、首行复选框对齐、外部底部安全区按钮/工具栏、单选编辑入口及对应测试已完成；未改 React，未建 UI 实验分支。
- 未测：Android/Windows 实机上的触摸手势、滚动感受与键盘焦点。
- Pre-existing 未跟踪文档仍在：`docs/STRATEGY_REVIEW_2026-09-08.md`、`docs/UI_INTERACTION_REVIEW_2026-09-08.md`、`docs/AI_UNIT_ECONOMICS_2026-09-08.csv`、`docs/ADR_FLUTTER_PRIMARY_2026-09-09.md`。

## 历史收尾（WP20-N）

- 本轮修改：Flutter 任务卡/矩阵/删除线/三语文案与对应测试，以及计划/交接/CHANGELOG/测试数量同步。
- Pre-existing 未提交文档仍在工作区：`docs/STRATEGY_REVIEW_2026-09-08.md`、`docs/UI_INTERACTION_REVIEW_2026-09-08.md`、`docs/AI_UNIT_ECONOMICS_2026-09-08.csv`（本轮未改）。
- 未测：Android/Windows 实机上的完成/多选/展开/删除线、读屏实际播报、进程级冷启动（Widget 仅重建 `MatrixHome`）；当时未测 Web，后续 WP20-W 已取消。
- 没有删除文件，没有改 Web 应用代码，没有引入后端。

## 历史收尾记录（原生审查轮）

- 会话最初工作区干净，无 pre-existing 用户改动；仅显式暂存本轮原生代码、回归测试和受影响文档。
- 本次 closeout 只更新交接任务及提交状态，没有继续修 B01，没有删除文件，没有重跑已经通过且代码未改变的测试。
- 重要文件：`lib/storage.dart`、`lib/ai_service.dart`、`lib/widgets/input_sheet.dart`、`lib/screens/`、三份新增 `test/*regression_test.dart` 及审查报告。
- APK、Windows Release 整目录及 `docs/native-*.log` 属于本地产物/忽略文件，不提交。它们保留用于复测与排查，不是删除候选。
