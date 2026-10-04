# WP17-Q2：修复截图任务结构漏检

基线 `459f9a28cefdcac9196825b2d4ac70250dbf3b8d`，分支 `codex/wp17-q2`，工作树 `D:/Dev_project/martix-wp17-q2`。提交身份只在本树设为 `wp17-q2-agent <wp17-q2-agent@local.invalid>`。`toolchain.json` 为 Flutter 3.32.8 / Dart 3.8.1（revision `edada7c56edf4a183c1735310e123c7f923584f1`，engine `ef0cd000916d64fa0c5d09cc809fa7ad244a5767`），SDK `D:/Dev_SDKs/Flutter_3.32.8`。未找到适用的 AGENTS.md。未改 main，未推送、amend、打 tag 或创建 Release。

## 两个缺陷

Q1 生成器 `native/ocr/tools/q1_quality.py` 有 8 景、30 条真值。复选框是 28px 矩形，含边界为 29px。`python native/ocr/tools/q2_structure.py expect` 退出码 0：旧规则 `0.022 * width` 只漏 `long-lines`（1600 宽，下限 35.2，2 条），其余 28 条仍在带宽内。

这两条的文字已被官方 OCR 认出，但扫描把 29px 方块丢掉，所以没有草稿。记录框为 `[37.14, 503.8, 1150.73, 65.73]` 与 `[39.54, 634.54, 1097.58, 57.58]`，短边 / 行高约 0.44–0.50，文字框从方块左侧开始。

8×8 白图的空文本框 `[-0.25, -1.25, 10.5, 10.5]`、分数 0，原先让整图适配抛错，捕获把它记成该图的 “Invalid PNG”。

## 改动

没有把 0.022 全局放宽。`gutter_scan.dart` 仍用旧带宽标记 `sizedByWidthFraction`。额外保留孤立方块：两边都 ≥ 18 且 ≤ `0.075 * width`，并且不在旧带宽里。18px 下限去掉碎点和细笔画。到 2048 上限时，旧标记仍抛 `too many gutter marks`；多出来的救援方块被跳过，图标噪声不能让旧扫描能接受的图失败。

`screenshot_adapter.dart` 只在下面的条件把救援方块当成复选框：它领着该行最宽文字（方块起点不晚于文字起点加一边，文字还向右伸出至少一边），并且 `min(边) / 行高` 在 `[0.38, 2]`。同一行若已有旧带宽标记，仍只用旧标记，完成态和层级保持 R2。顶栏截止 `0.22 * width` 和层级 `0.07 * width` 不变。未匹配标记的笔记只数旧带宽方块。

比值落在 `[0.25, 0.38)`、行宽至少 8 倍边长、并且方块领头的文字，成为待确认任务：`checked` 为 false，`checkbox_box` 为空，确认原因以 “task structure is uncertain; checkbox size does not match the text” 开头，不能自动提交。短标题（例如 “今日”）仍是章节，不变成任务。

空文本且坐标有限但越界：不抛错、不造任务，笔记写明有几个空白框在图外。空文本且坐标有效仍是噪声。空文本且坐标非有限，以及非空越界，仍抛错；捕获层对后者仍给出逐图 “Invalid PNG”。`screenshot_capture.dart` 未改。

未改选图、原生识别、预览确认/提交、模型锁、数据库、`test/helpers.dart`、共享 README/ROADMAP/导航/版本。`pubspec.yaml` 与 `pubspec.lock` 未改。

## 前后

2026-10-04 集成审查补修扫描额度：旧带宽标记与救援方块分别计数，最后优先保留旧标记并裁剪救援方块到总上限 2048。新增 2100 个救援方块先于正常复选框的回归，避免噪声占满额度后误报整图失败。

| 项 | 修复前 | 修复后 |
|---|---|---|
| long-lines 两条任务 | 文字在，草稿 0 | 两条都进草稿，未勾选/已勾选、level 0、无父任务、无日期、未确认 |
| Q1 三十条结构 | 28/30 | 30/30。checked、父行、日期空、未确认都对齐；`canSubmit` 仍为 false |
| 8×8 空越界框 | 整图适配失败 | 错误为空，任务 0，笔记说明框在图外 |
| 非空越界 “买菜” | 拒绝 | 仍拒绝 |
| R2 十二张注入对照 | 标题、完成态、日期、父子、排除标题 | 同一断言通过，黄金数据未重录 |

mixed-light 的官方 OCR 把邻近字形 “√夜” 粘进 “確認Task12完了”。配对用去空白后的 Levenshtein / 参考长度 ≤ 0.35，与 Q1 `score()` 的接受限相同；条数必须相等，checked、父 id、日期和未确认仍是硬条件。多一条或少一条会失败，不会靠放宽结构断言盖住。

刻意不收成任务的形状：10px 图标、90×14 日期条、五个相距 4px 的 20px 方块、短 “今日” 配 18px 方块。22px 方块配 40px 行高（1200 宽，低于旧下限 26.4）收成一条已勾选任务。

## 官方模型实跑

原 Agent 只读 `%LOCALAPPDATA%\wp17r2-assets`，五个文件匹配历史 `docs/evidence/wp17r2/assets.lock.json`；该锁的转换权重来源是 nihui 验证仓库，并非 I5 官方可再分发部署。此处原“官方模型”表述不成立，历史结果仅作验证证据。2026-10-04 集成端另用 I5 官方部署和 I8 Release DLL 重跑八图及生产适配回归，结果单独记录在集成日志，不以历史锁替代官方许可核验。

八张 Q1 合成图再识别一次。文字与框和已保存的 `native-raw.json` 一致，框差为 0。`long-lines`、`small-light`、`large-dark`、`japanese` 的 JSON 正文（去掉 id）完全一致。`mixed-light`、`mixed-dark`、`dense-subtasks`、`tiny-dense` 只有分数抖动，最大绝对差 0.0007，没有一行跨过 0.8 的低置信复核线。摘要在 `%LOCALAPPDATA%\wp17q2-private\live-ocr.json`。默认单测不读这个目录，也不下载模型。

## 命令

在工作树内，除非另注。

| 命令 | 退出码 |
|---|---|
| `python native/ocr/tools/q2_structure.py expect` | 0 |
| `flutter analyze --no-pub`（去掉多余 `!` 之后） | 0 |
| `flutter test --no-pub` 四个文件：`wp17_q2_structure_test.dart`、`wp17_q1_gutter_test.dart`、`wp17_i3a_screenshot_adapter_test.dart`、`wp17_i3a_screenshot_capture_test.dart`，并设置 `WP17_Q2_FIXTURES` 指向 Q1 合成目录 | 0，44 通过 |
| 只读官方模型八图再识别 | 0 |
| 默认 `flutter test --no-pub`（未设置 `WP17_Q2_FIXTURES`） | 0，1421 通过，12 跳过。日志 `%LOCALAPPDATA%\wp17q2-private\flutter-test.log` |

`WP17_Q2_FIXTURES` 未设置时，录制夹具那一条 skip。默认单测自己画像素，不需要字体或模型。

## 未验证

Android/arm64、低端设备、真实选图与点击、真实用户截图、物理桌面和长时间稳定性都没有跑。本包没有在 Linux 上重跑。WSL/Xvfb 不是设备通过。注入的 R2 OCR、同进程捕获和 skip 都不是独立进程或真机通过。
