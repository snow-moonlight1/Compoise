# WP17-I3b：截图入口、SAF 临时读取与确认提交

日期：2026-10-01。独立工作树：`C:\Users\20214\.codex\worktrees\wp17-i3a\martix`。
分支 `codex/wp17-i3b` 从集成提交 `ea6c4d0d8e58dd15e4c68d9824c9c0ac0bb445c6` 创建；保留原 `codex/wp17-i3a`。没有重复移植 I3a，也没有合并、改动主检出或推送。

## 入口与确认边界

首页“更多”新增截图入口，保留现有 HomeMorePanel 动作与详情草稿离开保护。新页面先检查本地组件，再允许选择；进入 picker 前再次检查。缺失/不可读模型、缺失 native 符号或清理失败明确显示失败。未配置外部组件的正常应用仍不可识别，不宣称正式支持，不下载或上传模型/图片，没有远程兜底。

默认模型位置为 application support 下 `wp17r2-assets/ncnn`，开发验证可注入 OcrRuntime 或编译时 `WP17_OCR_ASSETS`。检查五个模型/字典文件是否可读非空，以及 native 的四个 ABI 符号；这不是对任意模型内容、质量或许可证的认证。损坏模型或推理失败继续保留为逐图失败。

处理沿用 I3a 的适配、PNG 解码/gutter 检查和 R2 草稿契约；保留图片顺序、逐图失败、排除候选、确认原因和重复提示。新增 source loader/release/progress 接口将 SAF 一张一张接入同一个捕获批次，避免拆成多个失去预算/重复提示的小批次。返回 DraftBatch 后使用原 DraftPreview 校对，实时刷新可选目标清单。新界面和错误提示覆盖 en/zh/ja。

ScreenshotSubmission 只读取确认后 detached ImportSubmission：标题、勾选、根/子关系、目标清单、象限，以及用户主动保留的日期文字。日期不解析，不生成 deadline/plannedDate/reminder/completedAt；保留的原文转义为 Markdown 备注中的字面文本。默认不保留日期。根项和子项勾选各自保持，不因子项全部完成自动改根项。

每个流程维护 draft id → new Task/SubTask id 的稳定映射和固定创建时间，失败重试复用。同图较早的根项才能成为父项；跨图、嵌套子项、空标题、过长字段、伪造/过时快照和未确认草稿被拒绝。重复只是提醒，必须确认或明确跳过，不自动去重。

Store 只增加截图专用 batch 入口与确认回调门禁，复用原 applyImport 的排队、实时 rebase、单批提交和回滚；没有循环调用 addTask，也没有重写存储协议。排队前、事务取得所有权后和最后重算时检查确认/快照、实时清单及 board epoch，最后检查至 apply 之间没有 await。数据库仅接收普通任务字段，图像 id、路径/URI、bitmap、原始 OCR 行/框、排除候选及模型信息不进入任务库或日志。保存失败留在校对页，可重试；提交成功一次后关闭页面。确认前、取消和捕获页面卸载不写任务。

## I3a 内存政策的明确调整

本轮授权允许 Android 为现有 path-based native OCR 创建**有界、流程私有临时副本**。这调整了 I3a“无自建截图文件”的政策，不把复制后删除描述成始终只在内存。桌面保持现有 file_picker 多选 PNG 路径与资源限制；旧 ScreenshotCapture 的 Android file_picker 便利入口仍拒绝调用，产品页面改走独立 SAF。

Android 使用 ACTION_OPEN_DOCUMENT、CATEGORY_OPENABLE、image/png 和 EXTRA_ALLOW_MULTIPLE，仅临时读授权，不请求广泛存储权限，不持久保存 URI grant。URI 留在 Kotlin 会话内，Dart 只得到固定内部名称的私有路径。桥接没有 URI、文件名、路径、图像内容或 OCR 内容日志；没有修改 file_picker 插件或清空它的缓存。

| 边界 | 实现 |
|---|---|
| 数量 | 1–10 张；选择超额在读文件前拒绝，Dart loader 也先检查数量再分配 |
| 格式 | 先读 33 字节验证 PNG 签名/IHDR；静态 PNG 由 I3a chunk/decode 校验，其他格式/APNG 明确失败，无转换 |
| 实际外部流读取 | 单图硬上限 16 MiB、整批 48 MiB，包含失败尝试，不信任 provider 声明大小；32 KiB 分块 |
| 上限处行为 | 不额外读探测字节；无法在硬上限内确认 EOF 时保守失败。因此 SAF 接受单文件 **小于** 16 MiB，恰好 16 MiB 也失败；桌面沿用 I3a 的 ≤16 MiB 规则 |
| 解码 | 宽 ≤4096、高 ≤8192、单图 ≤12 Mi 像素、整批 ≤24 Mi 像素；完整复制/解码前检查头。失败尝试消耗已读取字节/已预留像素预算 |
| 磁盘 | cacheDir 的 `wp17-screenshot-import/session-<UUID>/image-<index>.png`，只创建本模块目录，拒绝目录别名/符号链接；一次只暂存一张 |
| 清理 | 适配每张后 release；失败、取消、卸载后 close。活跃 native 调用允许结束，再释放其路径；关闭失败不接受草稿且保留清理所有权供重试 |
| 崩溃残留 | Activity 初始化和选择前清理只属于本模块的 session 目录；不清全局 cache/file_picker，不删除非会话文件，不跟随别名 |

重复比较的压缩字节和 OCR/bitmap 中间数据只在捕获函数内存中。原有 Image/Codec 显式释放及串行 native/decode 队列继续使用。上述是输入与解码规模上限，不是 RSS、最慢 provider 读取时间或低端设备性能保证。

## 验证及实际退出码

Flutter 3.32.8 / Dart 3.8.1，Windows x64；Android API 23 x86_64 模拟器 `wp17r2api23`。没有跑全量测试或云端验收，留给集成人。

| 命令 | 最终实际结果 / exit |
|---|---|
| `flutter pub get --offline` | 成功，0；生成文件已恢复/移除 |
| 下列定向 Flutter 命令 | **151 通过、1 跳过、0 失败，0**；I3b 确定性测试 29 项，跳过项为需要设备 drive 的 SAF 测试 |
| `flutter analyze --no-pub` | No issues found，0 |
| `powershell -File test/wp17_i3b_android_stream_test.ps1` | Kotlin 2.0.21/JVM 流读取、尺寸/字节预算、取消、范围/专用残留清理断言通过，0；使用本机 Gradle 缓存，不联网 |
| `flutter build apk --debug --no-pub` | Debug APK 构建成功，0；未加入外部 OCR 模型或库 |
| 下列 `flutter drive` 命令 | 最新代码实际 SAF 多选/失败/清理/取消通过，0 |
| `git diff --check` / 暂存检查 | 通过，0 |

```powershell
$env:WP17_OCR_TEST_LIBRARY = 'D:\Dev_project\martix-wp17-i1\build\windows\x64\runner\Release\matrixflow_ocr.dll'
$env:WP17_OCR_TEST_ASSETS = Join-Path $env:LOCALAPPDATA 'wp17r2-assets'
flutter test --no-pub test/wp17_i3b_submission_test.dart test/wp17_i3b_capture_test.dart test/wp17_i3b_page_test.dart test/wp17_i3b_saf_device_test.dart test/wp17_i3a_screenshot_adapter_test.dart test/wp17_i3a_screenshot_capture_test.dart test/wp17_i3a_picker_test.dart test/wp17_i3a_native_capture_test.dart test/wp17_import_preview_test.dart test/wp17_i1_ocr_runtime_test.dart test/rf02_import_commit_race_test.dart test/rf11_import_target_test.dart test/ux02_regression_test.dart test/os21_page_coordination_test.dart test/os27_copy_test.dart test/platform_ui_policy_test.dart --reporter expanded
flutter analyze --no-pub
powershell -File test/wp17_i3b_android_stream_test.ps1
flutter build apk --debug --no-pub
flutter drive --no-pub --target=test/wp17_i3b_saf_device_test.dart --driver=test/wp17_i3b_device_driver.dart -d emulator-5554 --dart-define=WP17_SAF_DEVICE=true
```

确定性覆盖：选择取消/流程卸载和晚到结果、活跃 OCR 结束后清理、逐图失败/立即释放/重复只提示、释放失败拒绝草稿、模型/native 缺失不打开 picker、不可信数量、未经确认/过时提交、父子映射和嵌套阻断、实时清单删除/确认撤回/标题修改/取消、排队中的库新增、指针保存失败回滚及并发编辑保留、稳定 ID 重试、成功只提交一次。界面覆盖三语言实际 More→DraftPreview→Store 路径、逐图错误、320px+键盘+1.7 字号和实时目标删除。RF02/RF11 原存储/导入、UX02/OS21 首页/草稿、OS27 文案及 I1/I2/I3a 回归均包含在定向命令中。

开发中曾有 exit=1 的 widget fixture 定位/定时器清理问题、静态 lint，以及 More 高度导致 UX02 完成率未构建的真实回归；均修复，最后上述命令全通过。初次 JVM 编译器 classpath 缺 coroutines 导致 exit=2，复现脚本已包含依赖。直接将设备测试放在 test/ 下运行 `flutter test -d` 实际仍在主机执行并 exit=1；设备证据只采用后续 `flutter drive`。模拟器更新 APK 曾报 INSTALL_FAILED_INSUFFICIENT_STORAGE，Flutter 后续重装成功；没有据此宣称首个安装尝试成功。

### 实际设备桥接证据与限制

系统 DocumentsUI 通过临时 SAF grant 选择两张相同的 400×400 合成白底 PNG（各 1485 字节）和一张伪装为 .png 的 33 字节坏图。测试实际读取 content provider 流，沿 I3a 解码/适配；返回三张有序结果，其中坏图独立失败、两张相同图片仅提示重复，确认前不可提交。OCR 与可用性在这条测试中明确注入，**不是 Android 模型识别证据**。

测试实际确认返回草稿后专用目录为空、预置旧 session 副本被清除、file_picker 哨兵文件保留；再次打开系统 picker 后按系统返回，取消且无草稿，专用目录仍为空。第三次在系统 picker 打开期间主动 dispose；桥接 finishActivity 关闭本次选择器，晚到结果被抑制、目录仍为空；drive 停止应用后，ADB 的 resumed activity 为 Launcher，系统选择器没有残留。逐张 release 时序和活跃 native 结束后删除由 Dart 确定性测试验证。外部 provider 无限/超限流、字节数不可信和像素超限由共享的实际 JVM reader 测试覆盖；未声称已在设备上用恶意 provider 实测。

设备测试协调方法：ADB 推送上述三个**合成**文件到 Download；DocumentsUI 若 Downloads root 不列出它们，可启用“显示 SD 卡”后从内部存储/Download 选择。看到 `WP17_SAF_PICK_READY` 后多选三张并打开；`WP17_SAF_CANCEL_READY` 后按系统返回。第三次选择器由测试在 2 秒后自动 dispose，使用 WP17_SAF_DISPOSE_READY/DONE 信号。这些日志只是固定测试信号，未记录原图/OCR/URI/私有路径。

### Windows 外部模型真实识别

最终定向命令包含 I1/I3a 的五项外部原生测试，确实执行了 native OCR，未使用注入文本：12 张 R2 合成截图得到 128 项任务，标题/勾选/父项/日期文字与已有参考草稿一致；固定 10 图批次保持顺序和未确认门禁。DLL SHA256 为 `80de04573d9188084e6b7a0f254cb030c775aa06e1c516f3e659c019effd6809`。五个外部模型/字典文件 SHA256 本轮重新核对，与 `docs/evidence/wp17r2/assets.lock.json` 一致。没有提交模型、DLL、运行日志或新增 raw OCR 结果文件。

## 范围与剩余门禁

只改 screenshot_import 服务/页面、matrix_screen 入口、MainActivity 与新增 SAF Kotlin 类、Store 专用 batch 门禁、三语言 importReviewTitle 相邻区域的 screenshotImport* 键、本包测试和本记录。Planner、设置备份流程、备份契约/preflight、原生 C++ 算法、pubspec、ROADMAP 和其他翻译区域未改。

剩余：集成人的全量 Flutter/云端验收；转换模型再分发许可；Android arm64 真机的 SAF/内存峰值/真实 OCR；任意恶意或阻塞 content provider 设备测试；Windows/Linux 真实桌面 picker 与应用打包验证、Linux Flutter bundle；真实用户截图的识别质量与性能门槛。API 23 x86_64 的 SAF 验收不能替代这些门禁。
