# WP19-R 开发管理模式隔离原型

起点 `459f9a28cefdcac9196825b2d4ac70250dbf3b8d`，分支 `codex/wp19-r`，工作树 `D:/Dev_project/martix-wp19-r`。
本包只新增文件，未改任何产品源码；提交身份仅在本工作树生效（`git config --worktree`）。

## 结论（先看这条）

WP19 目前只有一个历史名字，没有获批的完整需求。用这份原型能确认的是：

- **唯一在现模型里没有落点的能力是「任务之间谁挡住谁」**。派生出的「可开始 / 等待 N 项 / 循环等待」和「完成后解锁哪几项」在普通模式（象限 + 标签 + 步骤 + 日期）里无法表达，也不该用标签硬凑——标签没有顺序，也没有完成语义。
- **阶段（设计/实现/验证/发布）可以复用现有标签**（WP12 标签 + 搜索页按标签 AND 筛选已经能做），只是没有固定顺序。
- **完成标准可以复用备注**（`notesMarkdown` 已可读写与搜索），只是不能结构化筛选。

因此建议：**不要按“开发管理模式”做整套新导航和新持久化模型**。若吸收价值，最小落地是给任务加一个「阻塞于（同项目内任务 id）」字段，并在今天页/矩阵页给一条“可开始/等待”提示；其余三项（阶段、验收、项目）用现有能力即可。若不做，本原型作为一次性验证保留在 `lib/experiments/` 或直接删除都可以——它不参与正常构建。

## 本包文件

- `lib/experiments/wp19_dev_mode/`：`main.dart`（显式入口）、`wp19_dev_mode_app.dart`（界面）、`wp19_dev_model.dart`（实验状态与意图）、`wp19_dev_data.dart`（13 个合成任务、2 个项目）、`wp19_dev_labels.dart`（中文文案）。
- `tool/wp19_dev_mode_compare.dart`：无界面对照与不变量探针（默认套件不收集 `tool/`）。
- `test/wp19_dev_mode_model_test.dart`、`test/wp19_dev_mode_view_test.dart`。
- 本文件。

## 原型怎么跑

```
flutter run -t lib/experiments/wp19_dev_mode/main.dart
```

`lib/main.dart` 与产品导航未改；`test/wp19_dev_mode_model_test.dart` 里有两条静态审计用例保证：实验目录不 import Store/持久化/平台服务/AI 层，且 `lib/` 下任何产品文件都不引用实验目录（所以正常构建不会打进去）。

界面在同一份合成数据上给两种组织方式：**普通模式**（象限分组，勾选只让任务换位置）与**开发视角**（阶段分组 + 阻塞提示 + 完成标准 + 解锁预览）。所有操作只写入内存意图日志：

- 意图类型：完成 / 撤销完成 / 批量完成 / 改阶段 / 加阻塞 / 去阻塞 / 改完成标准 / 清除实验字段 / 从会话移除。
- 每条意图记录 `before`/`after` 快照，`撤销上一步` 按 LIFO 精确回退；批量完成记 **1 条**意图，撤销一次整批回退；移除任务同时清掉指向它的阻塞关系，撤销一并恢复（有回归用例）。
- 「导出实验状态」给出 JSON（`wp19r.dev-experiment/1`），含派生 ready、等待项、未解析阻塞、循环链和意图日志；它不是备份格式，产品导入不认。
- 语义边界：跨项目的阻塞指针只报“阻塞项找不到或不属本项目”，不建立跨项目依赖；循环依赖允许存在但标红且两侧都不算“可开始”；退出实验会显示将丢弃的意图数与触及任务数，退出后 `写入产品库 0 次`，重载入的是同一份合成数据。

## 与普通模式重复的部分

项目分组（Board）、优先级（四象限）、自由标签（可当阶段）、步骤（SubTask）、截止/计划日与提醒（deadline/plannedDate/ScheduleItem）、多维筛选（搜索页）、批量选择（矩阵页选择模式）、撤销快照与过期保护（`TaskUndoSnapshot`/`canApplyUndo`）——这些产品已有，原型没有重做，也没有新建持久化字段。

## 需要用户决定才谈得上转正的范围

1. 依赖是否允许跨项目（原型：同项目内，跨项目只报缺陷）。
2. 阶段做成有序枚举字段（需迁移 + 备份 v4）还是标签约定（零成本、无顺序）。
3. 完成标准是独立字段还是复用备注。
4. 阻塞是否影响排序与提醒投递（原型只做提示，不改今天页顺序、不发通知）。
5. 循环依赖是否允许保存，还是录入时就拒绝。
6. 转正需要 en/zh/ja 三语文案；原型故意只有中文，未写入共享 `lib/l10n.dart`。
7. 转正需要产品级列表虚拟化；原型为可审查故意全量构建 13 行。

## 验证记录

工具链：Windows `D:/Dev_SDKs/Flutter_3.32.8`（Flutter 3.32.8 / Dart 3.8.1，与 `toolchain.json` 一致）。私有根目录 `D:/Dev_project/.wp19-r/`（日志、渲染图、临时输出），未写入产品数据目录。

| 命令 | 退出码 | 结果 |
|---|---|---|
| `git worktree add -b codex/wp19-r D:/Dev_project/martix-wp19-r 459f9a2` | 0 | 新树，名称此前不存在 |
| `flutter pub get --enforce-lockfile` | 0 | 未改 pubspec/lock；顺带生成 3 个未跟踪 `linux/flutter/generated_*`、3 个 `windows/flutter/generated_*` 行尾差异（均未暂存） |
| `flutter analyze --no-pub` | 0 | 无 issue |
| `WP19R_OUT=<私有根>/evidence flutter test --no-pub tool/wp19_dev_mode_compare.dart` | 0 | 2 个探针用例通过，打印组织对照并校验派生/撤销/导出不变量 |
| `flutter test --no-pub test/wp19_dev_mode_model_test.dart` | 0 | 12 通过：隔离审计 + 动作守卫 + 循环/解锁（含“穿过已完成任务的链不算死锁”）+ 会话确定性 |
| `WP19R_OUT=<私有根>/evidence flutter test --no-pub test/wp19_dev_mode_view_test.dart` | 0 | 16 通过：两种模式对照、完成/撤销、批量确认、导出内容、移除/撤销、退出/重载、筛选、360 dp 明暗×标准/200% 字号（每组独立用例并断言主题与缩放真的生效）、1100 dp 桌面、Tab 键盘遍历 + 空格完成、200% 下的两个对话框、SharedPreferences 种子库未被写 |
| `flutter test --no-pub`（默认全量，不设 WP19R_OUT） | 0 | 1442 通过 / 11 跳过，用时 2:21 |

界面证据（widget 渲染，非设备截图；测试字体不含中文，汉字显示为方块，与 `docs/evidence/wp13/README.md` 记录的同一限制）：

- `D:/Dev_project/.wp19-r/evidence/compare_report.txt`（`5df9f1ad00b51808b616e7d7d136d3790a915a7803c001c7eb8bec60e11dcbfc`）
- `D:/Dev_project/.wp19-r/evidence/export_state.json`（`c1fdcf907af31e7b33c089f0bb0b37ae8731e9c0bb35c728aef9cce28941e161`）

全量数与基线核对：1442 − 本包新增 28（12 + 16）= 1414，与 `459f9a2` 基线记录的 1414 通过 / 11 跳过一致，说明产品默认套件未被本包改变；`tool/` 探针不被默认套件收集。

过程记录（失败→修复，均为本包文件）：

1. 首轮 `flutter analyze` 报 4 条（测试文件的悬空库注释、多余 cast、多余 `!`）→ 修好后 `No issues found`。
2. 界面用例首轮 11 条全红：`ListView` 懒加载使未进入视口的行不存在，且阶段筛选把“未筛选”当成“筛空”。改为整页单滚动 + 显式筛选判断。
3. 对话框用例报 `No MaterialLocalizations found`：`showDialog` 用了 `MaterialApp` 之上的 context → 改为 `home: Builder(...)` 传页面 context。
4. 行内“更多”最初用 `PopupMenuButton`，移除该行时浮层锚点已失活触发框架断言 → 改为行内展开，同时更利于键盘。
5. 采集证据时发现 4 组明暗/字号截图实为同一状态（State 复用使开关互相抵消）→ 拆成每组独立用例，并断言 `Theme.brightness` 与 `TextScaler` 实际生效。
6. 环检测语义修正：穿过已完成任务的回环不是死锁，只报“等待”。

这些文件留在私有根目录，不入提交（截图/生成物）。渲染可由上面的 `WP19R_OUT=...` 命令重跑复现；本轮实际字节摘要：

- `render/phone_360_light_100.png` `48cc549ff2bd9ba69c5d3018e01504e0690f3a1f6314ad0fe1369658e029ef8d`
- `render/phone_360_light_200.png` `226b3fe5e4e537baf44ac6d88ab7de98396c86b709f90b019648962ba36b30f7`
- `render/phone_360_dark_100.png` `0533508170e96f530253f1421396b434bed1ae63d6a08a41e70435b568f334c2`
- `render/phone_360_dark_200.png` `9bbe6340e721a9be09bce4278dd28a7d6f1b3516230d32afab6e4f8223d8db9b`
- `render/phone_360_light_200_batch_dialog.png` `8112647a8239be5e6dc5571cc8b1fcb18e060d69c883c384294e637675a5677e`
- `render/phone_360_light_200_export_dialog.png` `3fb71e8a4a11b8e632844baa118271a42fcc2dcd07f94ef25e3429fc0477f165`
- `render/desktop_1100_light_100.png` `346aed65e159c39e23d8954203baff16e167cfa7c1c98fe7516a3185a0f98ada`
- `render/desktop_1100_light_normal_mode.png` `df312acfa2f53cf6f09aff856eca3ed2fd825735b5a793a3acf31e313ae6106e`

## 未验证

- 未在真实窗口或设备上手工操作：Android/Windows/Linux 的实际窗口、物理键盘与输入法、读屏器、系统级 200% 缩放都未测；`200%` 是 `TextScaler.linear(2.0)` 模拟，`360 dp` 是 `tester.view.physicalSize` 设定的逻辑视口。
- 未跑 `flutter build`（正常入口未改，构建入口未变由全量套件与静态审计用例支撑）；未安装任何 APK，避免覆盖 `com.matrixflow.app` 正常包身份。
- 未验证与 Store 并发写、备份导入导出、提醒投递的互操作——原型按设计不接这些。
- 未做设备/GPU 相关串行占用，无 AVD、无原生 GUI 会话。

## 给集成端的提示（本包未改，属边界外）

1. 共享 `D:/Dev_project/martix/.git/config` 里 `[user] name = wp18-r-agent`（WP18-R 写进了 common config，不是 worktree 作用域）。所有没有自己 `config.worktree` 身份的新工作树都会继承它。建议集成端清掉并让各包用 `git config --worktree`。
2. 基线 `459f9a2` 之后 main 已有 21 个提交（含 `f6d0c6e` planner 键盘修复、`abc182d` 八包集成）。本包按分派固定在 `459f9a2`，未跟随后续 main；集成时若基线漂移需重跑本包三条定向用例。
3. 本包只新增文件，无共享契约改动；`docs/README.md`、`docs/ROADMAP.md` 的 WP19 状态由集成端决定改不改（建议改成“已用隔离原型验证，结论：仅依赖关系缺位”，或直接标注不做）。
