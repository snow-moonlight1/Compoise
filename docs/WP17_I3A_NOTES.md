# WP17-I3a：多图捕获与 OCR 草稿适配验收

日期：2026-09-30。基线为 `origin/main` 的 `d65780c5e4037ba98a5a2cf9e1bc5418f4bad3f0`；独立工作树 `C:\Users\20214\.codex\worktrees\wp17-i3a\martix`，分支 `codex/wp17-i3a`。本包新增 `lib/screenshot_import/`、本包测试和本记录。没有修改 Store、备份、原生 C++、首页导航、`lib/l10n.dart`、`docs/ROADMAP.md` 或 I1/I2 接口。只提交本工作树，不推送。

## 实现与接入接口

`ScreenshotCapture(runtime: OcrRuntime(...)).pickAndCapture()` 使用现有 `file_picker` 的多选能力，按返回顺序给图片分配 `image-1` 等临时 id；`captureFiles()` 可接调用方提供的路径。选择级错误返回 `result.error`，取消返回 `result.cancelled`。成功处理的批次直接返回 `result.batch`，包括逐图失败，调用方可交给现有 `DraftPreview`。本包没有导航或任务库提交回调；I3b 负责挂载预览与最终写入。

```dart
final capture = ScreenshotCapture(
  runtime: OcrRuntime(assetsRoot: verifiedExternalAssetsRoot),
);
final result = await capture.pickAndCapture();
// I3b 显示 result.error；取消时结束流程；否则挂载现有 DraftPreview：
// batch: result.batch!, boards: ..., onSubmit: ..., onCancel: ...
// 原生推理不能中途强杀；流程取消/卸载时调用 capture.cancel()/dispose()。
```

`ScreenshotDraftAdapter.adapt()` 是纯适配接口，产生内存中的 `wp17r2-draft/1` 单图对象，再由捕获模块组装 `images/duplicates` 并调用 `DraftBatch.fromJson()`。原始 OCR 行索引、anchor、rows、noise 和复选框证据留在临时 wire 对象中，不扩展 I2 持久化或快照字段；返回的批次不含路径、原图字节、raw OCR 行或缩略图。

算法参考 [R2 草稿契约](WP17_OCR_EVALUATION.md#识别结果--可编辑任务草稿数据契约)、[adapter.py](evidence/wp17r2/tools/adapter.py) 与 [wp17r2lib.py](evidence/wp17r2/tools/wp17r2lib.py)：

- 按框纵向重叠合并行，按上下、左右位置排序，不依赖 OCR 数组顺序。保留原始行索引；顶栏 chrome、右侧 meta、无复选框的 section 保留为可恢复的排除候选。
- 左侧四分之一图像以背景灰度中位数、亮度差和四连通组件检测独立方形标记，沿用 R2 的尺寸、隔离间隙与 fill 阈值。暗色与浅色图一致；透明像素合成到白底。OCR 的 `V/√` 不能作为勾选依据，落在复选框内的识别块不混入任务标题；只有符号的行仍保留为待校对候选。
- 缩进只推断 0/1，父项指向同图较早的最近根任务源行。所有勾选态与层级推断均有待确认原因；孤立子项、多标记匹配、拆分文字块、低置信度和无标题分别提示。不会自动确认任何任务。
- 右半区元信息保留为原样 `due` 字符串并要求校对，不解析日期、截止时间或提醒；日期默认不随快照提交。内嵌标题中的日期仍是标题文字。重复按原始字节相等或标题字符集合相似度提示，始终 `hint_only: true`，不合并、不删除。字符提示只做空白/控制字符去除、大小写和全角 ASCII 归一化，不声称实现完整 NFKC。
- 逐图的读文件、格式、预算、解码、模型、native 与 OCR 结构失败保留在同一有序批次中，其他图片继续。任意原生错误/异常原文不会进入批次或日志。模型文件缺失/为空/不可读、native 库不可用都会明确说明 OCR 尚未正式可用；I2 直接显示单图错误。
- 同一 capture 防止重入，多个 capture 共享串行队列。取消/卸载后等待中的 picker、模型检查、解码或原生结果不能返回过期批次；调用方传入已取消 token 时则保留逐图 cancelled 记录。原生调用允许完成释放资源。源文件大小或修改时间在 OCR 期间改变时失败，避免把新图文字和旧图 gutter 混用。

## 资源和隐私边界

| 项目 | 上限/行为 |
|---|---|
| 图片数量 | 一批最多 10 张；超出整批拒绝，读图/解码/OCR 均不启动 |
| 格式 | 静态 PNG；扩展名和签名检查，JPEG/WebP/其他格式及 APNG 明确失败；不做转换 |
| 单文件 | 非空且不超过 16 MiB，依据真实 stat 而非 picker 声明值 |
| 批次压缩文件 | 合计 48 MiB；失败尝试也占已消耗预算 |
| 单图尺寸 | 宽 ≤4096、高 ≤8192、像素 ≤12×1024²；先读 33 字节 IHDR 再决定是否读完整文件/解码 |
| 批次解码负担 | 合计 ≤24×1024² 像素；达到预算的图片逐图报错，后续较小图片仍可处理 |
| 文件读取 | 最多 stat.size+1，文件增长/截短明确失败；PNG chunk 数 ≤10000，拒绝异常长度和动画 |
| OCR 输出 | 最多 2000 行、单块 8192 UTF-16 单元、全图 128 Ki UTF-16 单元；框/score 必须有限且有效；最多 2048 gutter 标记 |
| 分配与释放 | 每次仅一张 bitmap；gutter 扫描在 isolate；Image/Codec 显式释放后才调用 native；单张 RGBA 最大 48 MiB，扫描数组按 gutter 像素数线性分配 |

压缩原图只在本次函数局部内存中用于解码和重复比较，累计保留不超过文件预算；返回/取消后丢弃。没有自建截图副本、临时图像文件、OCR JSON 文件、数据库访问或 print/logger 调用。任务快照继续使用 I2 的确认门禁，原图、框、路径与 raw OCR 均不进入任务库。上述是输入/队列上限，不是进程 RSS 上限或低端设备性能承诺。

**Android 默认选择入口被明确关闭。** 锁定的 `file_picker` 8.3.7 的 `FileUtils.openFileStream()` 会无上限复制输入到 `cache/file_picker/<timestamp>/...`，并 `Log.i` 记录 URI；`withData: false` 不能阻止这两项行为，Dart 收到结果后再检查也太晚。这个包不能修改插件/原生入口，因此在调用 picker 前返回明确的隐私与资源门禁失败。没有通过清空整个插件缓存删除其他功能的文件，也没有把事后清理当作“原图只在内存”。Windows/Linux 默认 picker 使用多选 PNG 路径、关闭 compression/data/readStream；其他未验证平台明确不可用。可注入经过验收的未来 picker，但这不是 Android 产品能力已通过的证明。

## 验证

工具链：Windows x64、Flutter 3.32.8 / Dart 3.8.1，`flutter pub get --offline`。默认测试不依赖模型。测试中仅使用合成截图或临时自绘图；临时测试文件在 teardown 清除。

定向测试覆盖本包适配、捕获、picker、原生可选测试，以及原有 I1/I2 回归。确定性测试注入 R2 固定 OCR 输出，实际解码原 PNG；12 张样例的任务标题、勾选、父项、日期原文、排除候选和顺序与已提交的 R2 参考草稿逐项一致。另覆盖坏/伪装/超尺寸/空/超大小 PNG、动画、两类批次预算、声明大小造假、缺路径、异常 OCR、模型缺失可见失败、取消、重入和跨实例串行；原图仅产生重复提示。

复现命令（仓库根目录，Flutter SDK 已在 PATH）：

```powershell
flutter test --no-pub test/wp17_i3a_screenshot_adapter_test.dart test/wp17_i3a_screenshot_capture_test.dart test/wp17_i3a_picker_test.dart test/wp17_i3a_native_capture_test.dart test/wp17_import_preview_test.dart test/wp17_i1_ocr_runtime_test.dart --reporter expanded
flutter test --no-pub --reporter expanded
flutter analyze --no-pub
```

最终结果：

- 定向测试（设置外部模型/库，上述 6 个测试文件）：58 项通过，无跳过；其中本包确定性测试 35 项，外部模型端到端 2 项。
- 全量 `flutter test --no-pub --reporter expanded`：1066 项通过、5 项跳过、0 失败。跳过的正是本包 2 项及 I1 3 项需外部模型的测试，它们已在上面的单独真实识别测试中通过。
- `flutter analyze --no-pub`：No issues found；本包 Dart 格式检查 0 changed；`git diff --cached --check` 通过。
- `pub get` 产生的平台注册文件已恢复/移除，最终只新增本模块 3 个 Dart 文件、本包 5 个测试/支持文件和本记录；没有带入生成文件、模型、二进制或 OCR 结果文件。

### 外部模型真实识别证据

单独设置以下变量后运行上述定向命令；没有设置时本包 2 项和原 I1 3 项真实识别测试跳过，不能算作识别证据：

```powershell
$env:WP17_OCR_TEST_LIBRARY = 'D:\Dev_project\martix-wp17-i1\build\windows\x64\runner\Release\matrixflow_ocr.dll'
$env:WP17_OCR_TEST_ASSETS = Join-Path $env:LOCALAPPDATA 'wp17r2-assets'
```

本轮实际加载 I1 的 Release DLL，SHA-256 `80de04573d9188084e6b7a0f254cb030c775aa06e1c516f3e659c019effd6809`。I1 检出的原生源文件与本包基线源文件 SHA-256 相同，均为 `b4306870d58a7018f986bc4397fd817d9d86d5f834d82a8c479cef9428217093`。五个外部模型/字典文件均重新对照 [assets.lock.json](evidence/wp17r2/assets.lock.json) 的 SHA-256 通过；模型及 DLL 不提交。

`wp17_i3a_native_capture_test.dart` 实际跑通 OCR → PNG gutter → DraftBatch：12 张样例共 128 个任务，标题、勾选、父项和日期原文与参考草稿一致，仍全部未确认；固定十图批次成功并保持输入顺序（20,003,760 像素，未超过本包预算）。I1 的原生回归另外核对原始文字完全一致、框各分量误差 ≤1，并验证缺模型/坏 PNG/重复调用/取消。原生 ncnn 发出了模型层兼容性诊断，不包含截图或 OCR 文字；没有另存本轮原图或 OCR 中间 JSON。以上都是合成语料上的 Windows 证据，不是自然截图、Android 真机或整条产品入口验收。

## 剩余门禁

1. I3b：导航挂载、目标看板与一次确认写库、提交前 Store 校验；本包按范围保持未接线。
2. Android picker 必须先解决复制原图到磁盘、URI 日志和选取阶段无上限的问题，才能开放默认入口。本包拒绝触发当前实现。
3. PP-OCRv5 第三方转换权重再分发来源/许可、正式模型供应与缺模型的产品体验，仍沿用 I1/R2 未关闭状态。
4. Android arm64-v8a 真机运行和低内存设备的实际峰值/耗时/中断；Linux Flutter bundle 与平台 picker；Windows 真正的系统选择器交互和完整产品流程。本包只测 picker 参数合同、Windows DLL 与 Flutter 校对组件，不宣称这些平台入口均已验收。
5. 真实应用截图质量、删除线、复杂/多级父子关系及可靠日期解析；保守人工确认继续是必要步骤。只提供 PNG，其他格式转换不在本包。
