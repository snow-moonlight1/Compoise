# WP17-A1：官方模型 arm64 Android 验收探针

2026-10-03（Asia/Shanghai）。固定基线 `459f9a28cefdcac9196825b2d4ac70250dbf3b8d`，分支 `codex/wp17-a1`，工作树 `D:/Dev_project/martix-wp17-a1`，仅本树身份 `wp17-a1-agent <wp17-a1-agent@local.invalid>`。未找到适用 AGENTS；已读 I5/I6/I7/Q1 NOTES、官方 bundle 和 Android 驱动。完整提交 SHA 在外部 `handoff.json`，避免文档自引用。

**交付已编译的诊断 APK、arm64 Debug/Release 原生探针与默认关闭的宿主驱动；arm64 设备验收仍未通过。** ADB 实查只有 `emulator-5562 offline`，ABI/SDK/包身份均不可读；本机现有 API23/API35 镜像均为 x86_64。本轮没有安装任何 APK、启动 AVD、使用真实手机或以历史 I4/x86_64 结果替代官方 arm64 证据。

## 改动及设备入口

仅新增 `native/ocr/tools/a1_android.py`、`a1_driver_test.py`、`test/wp17_a1_device_test.dart` 和本文。Android Gradle/manifest/MainActivity、算法、SAF、模型锁、Store/SaveProtocol、正常入口、依赖、test/helpers.dart 和共享文档均未改；未派 Agent、发跨会话消息、push/amend/tag/Release 或使用发行签名。

设备入口使用生产 `LocalScreenshotBackend`、真实 ACTION_OPEN_DOCUMENT/SAF、native OCR、DraftPreview 和 Store；只沿用 saveWriter 故障与空凭据接缝。以下断言已实施并随启用的 APK 编译，**本轮均未在 arm64 执行**：

- 真实选择取消零 Store 写入；十图识别后未确认不能提交、取消零写入。
- 识别开始后通过真实页面取消，等活动调用与临时 PNG 清理完成，再执行第二个完整十图批次。
- 中/英/日各三张字节相同的原 R2 合成图加坏 PNG；逐图核对原 title/checked/parent/due，显式跳过重复图、确认所有候选与重复提示、改标题、保留日期原文并选板/象限。
- 实际 pointer 写失败保留校对、Store 和旧 pointer；一次 UI 重试仅一个成功 pointer，ID 与失败槽保持一致。结果为 18 根 + 6 子项、6 完成；日期不自动产生 deadline/plannedDate/reminderAt/completedAt。
- 第一应用在完整 suite/teardown 结果落盘后自行退出；第二应用从同一磁盘创建生产 Store，深比板、任务全部字段/子项、ID、备注、完成态、日期、设置、schedule 和 pointer。expected.json 仅作比较。
- Debug/Release 独立 smoke 分别做冷单图、同会话三批十张有效图、坏 PNG 后恢复、缺字典；检查真实远端退出 sentinel、原 R2 文本与几何，强杀/残缺输出拒绝。应用内也执行缺字典/坏 PNG/恢复检查。

宿主要求当前专用设备 serial/fingerprint 的显式 enrollment，拒绝 offline、非 arm64、API<23 和已有诊断包；串行使用 `Local\MatrixFlow-WP17-device-<serial>` Windows mutex，集成端其他驱动须共享该锁。只操作自己安装的 `com.matrixflow.app.wp17i6` 和每轮 UUID 目录，不改全局设置、日志缓冲或正常应用数据。未知 DocumentsUI 失败关闭，未提供 picker/OCR/bitmap 注入替代路线。

内存采样保留原 dumpsys meminfo 与 /proc/status：Java/Native heap PSS、支持时的 heap RSS、整进程 RSS/PSS、累计 VmHWM 分列；缺字段为 null。阶段包含 picker/review 等待，HWM 不当作每批可重置峰值，250ms 采样可能漏短峰。native smoke 时间不含模型加载，host wall 含进程/模型/ADB；Dart cold/hot 调用和完整 SAF 流程耗时另列，文件系统冷缓存不受控。Android am 无 waitpid，进程自然消失、suite 结果、退出意图与 `os_exit_code=null` 分开记录，并拒绝检测到的 crash/force-stop；不声称取得 Android 应用 OS 退出码。

## 实际产物与检查

私有根 `W=D:/Dev_project/martix-wp17-a1-private`，含源码镜像、PUB/Gradle/临时缓存、官方部署、SDK 副本、日志和产物。输入 Flutter `D:/Dev_SDKs/Flutter_3.32.8` 与最终 `W/flutter` 均校验 toolchain.json 的 Flutter 3.32.8 / Dart 3.8.1 和完整 framework/engine revision；Android SDK `D:/Dev_SDKs/Android_studio_SDK`，NDK `28.0.12433566`，JDK17，CMake/Ninja，编译 `android-23`。

官方部署从 I6 缓存只读核验后复制；现行 stager 检查官方 provenance、权重、字典及全部许可。五模型文件合计 10,717,392 B；arm64 ncnn 静态库 SHA256 `ff736cecd9851452724f3cb1fc47c40d789f83a805ba5855cdcc91eb80c77870`，stb SHA256 `594c2fe35d49488b4382dbfaec8f98366defca819d916ac95becf3e75f4200b3`，沿用 ncnn pin `c6b351b56fbe32e0381ae00331e3df649b20d7b7`。源缓存和锁未写入，未下载/转换模型。APK 的 12 文件/manifest 逐字节验 hash；原 R2 十图夹具 779,871 B / 13,637,160 pixels，符合原 48 MiB / 24 Mi 像素预算，逐图摘要在 `W/logs/fixtures.json`。

| 产物（均在 W，不提交/不安装） | 字节 | SHA256 |
|---|---:|---|
| native/Debug/libmatrixflow_ocr.so | 41,840,344 | `44eaa9c5414e0ed49c47662ff0bb2e02a9dfd6e65268a9c524c6c23dbbd7886a` |
| native/Release/libmatrixflow_ocr.so | 41,762,240 | `9cb55c153ce533b325d2ab7144278995d4731e0dfe7132928e49b0d48cb06270` |
| artifacts/wp17-a1-arm64-probe.apk | 132,811,072 | `5baeaac6bd4d65e904d9ebe8a152ffc266efebf393183d3ebf13b4b6a9cadf80` |
| artifacts/wp17-a1-normal-build-only.apk | 91,313,992 | `d55097a21193ceceec8677fbda901c88a3ecfacc7b68197bf81f4e59297f523a` |

两种原生库和 smoke 的 ELF64/AArch64、四个 C ABI 导出、NEEDED 与 CMake API23 配置实查通过；APK arm64 native 为 Debug、剥离后 6,633,816 B，SHA256 `34f4ef40364b9bc1109efb02a7ababddf35e33b4ccc768a68877b8af0742bb3f`。诊断 APK 身份 `.wp17i6` / minSdk23；普通 APK 为 `com.matrixflow.app` / 默认 main，确认没有 OCR 库或模型。均为常规 debug 构建，不是发行产物。

| 实际命令/检查 | exit / 结果 | W/logs 证据 |
|---|---|---|
| Flutter `pub get --enforce-lockfile` | 0，两次；锁字节不变 | pub-get.log、pub-get-final.log、checks.json |
| Flutter `analyze --no-pub` | 0，No issues | analyze-final.log |
| 定向六文件 Flutter 回归 | 0，58 passed / 1 opt-in skipped | targeted-final.log |
| Flutter `test --no-pub --reporter=expanded` 默认全量 | 0，1413 passed / 13 skipped | flutter-full.log |
| Python `-B -m unittest discover -s native/ocr/tools -p a1_driver_test.py -v` | 0，13 宿主契约回归 | driver-tests-final.log |
| `a1_android.py build --enable` / `normal-build --enable` | 0 / 0；native configure/build/readelf 也均 0 | commands.jsonl、native-builds.json、apk.json、normal-apk.json |
| stager `--check`、Dart format、Python AST、git diff --check | 均 0 | bundle-final-check.log、dart-format.log、handoff.json |
| 明确启用、空授权文件的 offline 设备尝试 | 1，正确拒绝，未 install | offline-device-refusal.log、device-inventory.json |

构建/Flutter/ADB 主命令的实际参数、cwd、退出码和耗时在 `W/logs/commands.jsonl`；依赖初始化/最终串行验收脚本为 `W/bootstrap.py`、`W/final_verify.py`。完整提交、其他定向命令及源文件边界由 `W/handoff.json` 补充。定向文件是 A1 device 默认关闭入口、I3B page/submission/capture、I3A screenshot_capture 与 Q1 gutter。上述注入式单元测试和 skip 只计宿主回归，不计 native/SAF/独立进程设备通过。

已有私有材料可复跑 `python -B native/ocr/tools/a1_android.py build --enable` 和 `normal-build --enable`；仅获授权的专用 arm64 设备才运行 `accept --enable --serial <实际序列号> --enrollment <用户确认的JSON>`。JSON schema=1、scope=`WP17-A1`、kind=`dedicated-test-device`（或已明确归属的 `owned-avd`）、serial/fingerprint 必须匹配 inventory；不会从旧报告自动生成授权。

## 保留失败、隔离与未验

初次镜像复制使用错误相对路径，Copy-Item 报错，但组合命令末尾的基线 analyze exit0；未将该次当 A1 分析。改绝对路径同步后最终完整源 analyze0。首次 APK 构建使用固定 SDK，发现 Gradle included-build 仍使用 SDK 工具缓存、Kotlin 使用全局 daemon 发现目录；最终复制同版本 SDK 到私有根，禁用 Gradle daemon/并发并改 Kotlin in-process，完整重建诊断/普通 APK 均0。未清共享 SDK/全局 Kotlin 目录。一次组合强停/递归清临时目录被工具策略拒绝、未执行；改为私有 Gradle 正常 stop、Kotlin 自行退出和边界核对后的可逆私有移动，清理完成。

`W/logs/cleanup-final.json` 实查本包活进程为空、device_installs=0、avds_started=0、tmp 为空；临时诊断内容留 `W/evidence/temp-retained`，模型、夹具、产物和日志保留。原 `emulator-5562` 没有被操作或清理。

**未验：arm64 真实 SAF 全流程、十图取消/重试/独立进程重开、Debug/Release 的设备原生识别和拒绝路径、Java/Native/整进程设备资源峰值及耗时、API23 arm64 运行边界、其他 DocumentsUI/locale、真实截图、低端机与长时间稳定性。** 没有设备流程/资源报告，`runtime_api23_verified=false`；编译、宿主回归和默认 skip 不关闭这些门禁。没有发现需越界修改 I8 平台接线的实测缺陷。
