# WP17-I4：OCR 模型来源与三端构建

状态：同一份 `native/ocr` 源码、同一份 PP-OCRv5 mobile ncnn 权重，本轮在 **Windows Debug/Release Flutter bundle、Linux Flutter release bundle、Android API 23 模拟器（x86_64）和 Android 16 arm64 真机** 上都实际加载并识别了 12 张 R2 合成图。准备脚本可从空缓存建立、哈希不符拒绝、离线复用。转换权重的再分发授权仍未关闭：本轮唯一验证过的权重来源（nihui 转换）没有声明授权，官方权重只做到“输入哈希固定 + 转换脚本就绪 + 工具链阻塞记录”，因此这**不是正式产品支持**。

日期：2026-10-01。分支 `codex/wp17-i4`，独立工作树 `D:\Dev_project\martix-wp17-i4`，从集成提交 `0c36b36da336f4c6551ccf93c49b567cde51f414` 创建。本包为**单个提交**：24 个文件、3600 插入 / 63 删除，父提交即上述基线；提交哈希不在本文件内自引用，交接报告给出当前值。未推送、未 merge、未改写基线提交。主检出保持干净，除三条未跟踪的 `linux/flutter/generated_*`（Flutter 在 Linux 插件启用时生成的注册文件，main 检出里同样未跟踪、`.gitignore` 未覆盖）之外没有其他残留。

固定工具链：Flutter 3.32.8 / Dart 3.8.1（`D:\Dev_SDKs\Flutter_3.32.8`，revision `edada7c56e`）；WSL2 Ubuntu 24.04.4，clang 18.1.3；Android NDK r27b（独立 native 构建）与 NDK 28.0.12433566（Gradle/Flutter 构建）；Visual Studio 2022 17.14。

## 1. 依赖与模型来源、再分发依据

外部目录是本机资产根 `%LOCALAPPDATA%\wp17r2-assets`（部署根 `%LOCALAPPDATA%\wp17i4-deploy`），全部不进仓库。

| 组件 | 固定标识 | sha256 | 授权与结论 |
|---|---|---|---|
| ncnn | `Tencent/ncnn` @ `c6b351b56fbe32e0381ae00331e3df649b20d7b7`（`third_party/ncnn_pin.txt`） | `LICENSE.txt` = `3a066e39806976fe274a042929523c68821c54bcf73369ed61aae2717edd54e8` | BSD-3-Clause，可随附声明再分发 |
| stb_image.h v2.30 | `nothings/stb` | `594c2fe35d49488b4382dbfaec8f98366defca819d916ac95becf3e75f4200b3` | 文件头声明 public domain，上游另给 MIT/Unlicense，可再分发 |
| PP-OCRv5 字典 | `PaddlePaddle/PaddleOCR` `ppocr/utils/dict/ppocrv5_dict.txt`（1553 行） | `d1979e9f794c464c0d2e0b70a7fe14dd978e9dc644c0e71f14158cdf8342af1b` | 仓库 Apache-2.0，可再分发 |
| PP-OCRv5 mobile 权重（**当前使用的 nihui 转换**） | `nihui/ncnn-android-ppocrv5` 的 det/rec `ncnn.param/bin` | det param `358f459680ae0e7a73e477469e529ce116f68c629019ec7a0b6457d2d9117934`、det bin `857a96bc963725105b78a178dfcc3c0c3db1a7b9eef32244367b2cb105ccf60b`、rec param `f52a6586ac3338d8c350db0c9f3c55ff2ecd3763327f9bc7f0efc091f8a63e74`、rec bin `49d9907a55ba20fa6637f9f788f66ab00793bc8ce57a733a09dbe86b9a2e3db0` | **无授权声明**：`GET /repos/nihui/ncnn-android-ppocrv5/license` 返回 404，README 只给转换配方。**仅用于验证，不得进发行包、不得提交仓库** |
| PP-OCRv5 mobile 权重（**官方来源**） | `PaddlePaddle/PP-OCRv5_mobile_det` / `_rec`（Hugging Face，model card `license: apache-2.0`） | 固定于 `native/ocr/tools/models.lock.json`（6 个输入文件，例：det `inference.json` `05feef1acb00aa4cd7362b15f7f501fc4f99d7b1fa73c1c871e0c7b1504b0f5c`、det `inference.pdiparams` `afa1820cb16c1fd0dad589d0f8b389139061c1ef6d68019685fd07be997dda5b`、rec `inference.pdiparams` `2460da90875937c94db97eba74ae3d9e5d4c4c57c42f1f41531c09a26bcc771a`、rec `inference.yml` `5dfeb2777f6d0db8177d8128a8acfcf6e6276dc4ac73ea3bf0dc06d6a5e85d8e`） | 本轮选定的明确授权输入路线；**转换未完成，见下** |

授权证据链接：

- 模型卡授权声明：<https://huggingface.co/PaddlePaddle/PP-OCRv5_mobile_det>（`license: apache-2.0`，API 字段 `cardData.license` 与标签 `license:apache-2.0`）
- 同上 rec：<https://huggingface.co/PaddlePaddle/PP-OCRv5_mobile_rec>
- ncnn 许可：<https://github.com/Tencent/ncnn/blob/c6b351b56fbe32e0381ae00331e3df649b20d7b7/LICENSE.txt>
- stb：<https://github.com/nothings/stb/blob/master/stb_image.h>
- PaddleOCR 字典与仓库许可：<https://github.com/PaddlePaddle/PaddleOCR>
- 转换配方（仅作过程参考，其产物无授权）：<https://github.com/nihui/ncnn-android-ppocrv5>

本包专用 notices：`native/ocr/THIRD_PARTY_OCR_NOTICES.md`。公共总表由集成端合并；其中标为 **not cleared** 的行不得并入。

### 官方权重的可复现转换：已脚本化，本轮未能产出

`native/ocr/tools/convert_models.py` 实现固定工具链、固定下载源、逐文件 sha256 校验、失败即退出，并把输入与产物哈希写入 `models.lock.json`（不静默改写已固定的摘要）。本轮已把 6 个官方输入文件的哈希固定下来，但**转换链路被工具链阻塞**，实测记录：

| 尝试 | 结果 |
|---|---|
| `paddle2onnx==0.9.2`（PyPI 上唯一可用于 cp313 的版本） | 依赖 `paddle.fluid`，Paddle 3.0 已移除，导入即 `ModuleNotFoundError` |
| `paddle2onnx==1.3.1` + `paddlepaddle==3.0.0`（cp312 venv） | 命令行可运行，但对官方 `inference.json` 直接报 `[Paddle2ONNX] Paddle model parsing failed`；该文件 `base_code.magic = "pir"`，需要能读 PIR 的转换器 |
| `paddlex --paddle2onnx`（PaddleX 3.7.2，要求插件 `paddle2onnx==2.0.2rc3`） | 装上 2.0.2rc3 后 `ImportError: DLL load failed while importing paddle2onnx_cpp2py_export`（本机缺其原生依赖）；插件探测因此报 “Paddle2ONNX is not available” |
| `paddlepaddle==3.2.2` + rc 插件 | 同上，DLL 仍加载失败 |

因此：**发布阻塞仍在**。已交付可执行脚本、固定输入哈希、固定转换参数（det `inputshape=[1,3,320,320] inputshape2=[1,3,256,256]`、rec `inputshape=[1,3,48,160] inputshape2=[1,3,48,256]`、`fp16=1`、opset 11）与失败记录；一旦在有完整 Paddle2ONNX 原生依赖的环境中跑通，`tool/prepare_ocr_assets.ps1 -ModelSource official` 会自动改用官方产物，并校验 `models.lock.json` 里的产物哈希。**在此之前不要把 nihui 权重描述为可分发。**

## 2. 准备/构建脚本（可执行）

| 文件 | 作用 |
|---|---|
| `tool/prepare_ocr_assets.ps1` | 下载/校验/缓存字典与 stb、固定 ncnn 源码提交、部署 `<DeployRoot>/ncnn` 的五件套、可选重建 ncnn host 树、可选官方权重转换、写出 `deployed.json`；`-Check` 只读校验、`-Offline` 断网复用、`-CleanWork` 只删自己的 `wp17i4-work`、`-ModelSource nihui\|official`、`-SkipNcnnSource` |
| `tool/build_ocr_windows.ps1` | Windows ncnn + `matrixflow_ocr.dll` + smoke 调用器，同一套 CMake 参数 |
| `tool/build_ocr_android.ps1` | NDK 独立构建两个 ABI 的 `libmatrixflow_ocr.so` 并打印 ELF NEEDED/SONAME 与 note |
| `native/ocr/tools/build_ncnn_linux.sh` | 固定提交、固定选项地重建 Linux ncnn 安装树 |
| `native/ocr/tools/build_linux_bundle.sh` | 带 OCR 依赖的 Flutter Linux bundle + 部署目录暂存 |
| `native/ocr/tools/run_linux_bundle_test.sh` | Xvfb 下跑 bundle 集成测试（`flutter test -d linux`） |
| `native/ocr/tools/convert_models.py` + `models.lock.json` | 官方权重 → ONNX → ncnn 的固定转换与哈希台账 |
| `native/ocr/tools/make_reference_fixture.py` | 从 R2 基线生成仅含几何的紧凑 fixture（`test/support/wp17_i4_r2_geometry.json`，基线 sha256 `d630850aa3be6fdd280a2f873fb4e980dd9ce648d60063a3595f115c25ed5494`） |
| `native/ocr/tools/android_smoke.sh` | 设备侧跑 smoke 并打印汇总行 |

边界：脚本只在资产根/临时目录写文件；仓库内不写模型、DLL/SO、APK、缓存或日志；哈希不符时拒绝覆盖并退出（退出码 3），离线缺件退出 4，缺工具退出 5，用法错误退出 2。

## 3. 实测结果

### 3.1 准备脚本行为（Windows，`powershell -File`）

| 场景 | 实际结果 / exit |
|---|---|
| 空缓存 + `-Offline -SkipNcnnSource -Ncnn none` | `ERROR: offline: ncnn/ppocrv5_dict.txt is not cached`，**4**（拒绝，未联网） |
| 空缓存联网准备 | 5 个模型文件落到部署目录，字典 1553 行，`deployed.json` 写出，**0** |
| 同一缓存 + `-Offline` | 全部 cache hit，不再联网，**0** |
| 篡改 det bin 一字节 | `... has sha256 110cc02c... but 857a96bc... is pinned`，**3**（不静默替换） |
| `-Check` 于篡改缓存 | 报同一处不一致，**3** |

### 3.2 Windows（Flutter 3.32.8，x64）

| 项 | Debug | Release |
|---|---|---|
| `flutter build windows --debug/--release --no-pub`（`WP17_OCR_NCNN_DIR`/`WP17_OCR_STB_DIR` 指向外部 ncnn/stb） | 成功，0（331.8s） | 成功，0（381.5s） |
| `matrixflow_ocr.dll` | 20 981 760 字节，sha256 `3e7a04962104763acdc308fe7ae9ce123b88211c4094ea5ca21a647ddb65a2c6` | 14 126 592 字节，sha256 `b6a577caaa5d4a9a618a58df737e875e9e86bd4038ad90bf91c832d5a64836e2` |
| `compoise.exe` | 1 247 744 字节 | 247 296 字节 |
| 位置 | 均在 `build\windows\x64\runner\<Config>\`（安装规则写在可执行文件旁） | 同 |
| 依赖（`dumpbin /dependents`） | `MSVCP140`、`VCOMP140`、`VCRUNTIME140(_1)`、api-ms-win-crt-*，**没有** `MSVCP140D`/`ucrtbased` | 同 |

DLL 与 `compoise.exe` 同目录这一点正是 `resolveOcrLibraryPath()` 与 `windows/CMakeLists.txt` 的安装目标一致的地方。

识别（12 张 R2 合成图，`test/wp17_i1_ocr_runtime_test.dart` 的 baseline 对照：逐行文字完全一致、矩形每分量 ±1）：

| 命令 | 结果 / exit |
|---|---|
| `flutter test --no-pub test/wp17_i1_ocr_runtime_test.dart`（`WP17_OCR_TEST_LIBRARY` = Debug DLL） | **5 通过**，0；日志 `02:19 +5: All tests passed!` |
| 同上，Release DLL | **5 通过**，0；日志 `01:51 +5: All tests passed!` |
| `flutter test --no-pub test/wp17_i1_ocr_runtime_test.dart test/wp17_i4_assets_test.dart`（Release DLL） | **14 通过**，0 |
| `flutter drive --no-pub --target=test/wp17_i4_bundle_ocr_test.dart --driver=test/wp17_i4_device_driver.dart -d windows`（进程环境 `WP17_OCR_ASSETS`） | **通过**，0。`WP17_I4_ASSETS_ROOT=C:\Users\20214\AppData\Local\wp17i4-deploy`、`WP17_I4_LIBRARY=...\Debug\matrixflow_ocr.dll`、`WP17_I4_AVAILABILITY_OK`、`WP17_I4_BUNDLE_RESULT images=12 lines=274 elapsed_ms=8942`、`00:09 +2: All tests passed!` |

Release DLL 的独立 smoke（`matrixflow_ocr_smoke`，12 张图一次会话）：`images=12 succeeded=12 elapsed_ms=141456.3 peak_rss_kb=468972`，exit 0；合计图片字节 1 271 784。该耗时是这台机器上（同时有其他构建/测试在跑）的实测值，不是性能门槛。

错误边界（Release DLL）：缺图 `cannot open image`；空文件与 >16 MiB `image file exceeds 16 MiB or is empty`；坏 PNG `PNG header decode failed`；宽 4097 / 高 8193 / 4000×3200 `image dimensions exceed OCR limit` 且宽高为 0；缺模型目录 `cannot read dict`；重复调用结果一致；取消后剩余项 `cancelled`。

### 3.3 Linux（WSL2 Ubuntu 24.04，Flutter 3.32.8 linux-x64）

- `native/ocr/tools/build_ncnn_linux.sh`：742 个目标，`libncnn.a` + 头文件装到 `~/wp17i4-ncnn-linux/install`，0。
- `native/ocr/tools/build_linux_bundle.sh`：`flutter build linux --release` 成功，**bundle 里出现 `bundle/lib/libmatrixflow_ocr.so`（16 940 360 字节）**，这是 I1 记录里“没有跑过 Flutter 打包规则”的那一条，本轮补上；profile 构建同样带该库（17 062 552 字节）。
- 该 bundle 的 `lib/` 里同时有 `libapp.so`、`libflutter_linux_gtk.so` 与四个插件 `.so`；CMake 安装目标与 `CMAKE_INSTALL_RPATH=$ORIGIN/lib` 一致。
- 实际加载与识别：`native/ocr/tools/run_linux_bundle_test.sh`（Xvfb :99，`flutter test --no-pub -d linux`，进程环境 `WP17_OCR_ASSETS=/home/ubuntu/wp17i4-linux-deploy`）：
  - `WP17_I4_ASSETS_ROOT=/home/ubuntu/wp17i4-linux-deploy`（来自进程环境，即产品解析顺序的第一项）
  - `WP17_I4_FILE ppocrv5_dict.txt exists=true bytes=74012` 等 5 行：部署的五件套逐个可读且非空
  - `WP17_I4_BUNDLE_RESULT images=12 lines=274 elapsed_ms=7997`
  - `00:15 +1: All tests passed!`，exit 0（含坏 PNG 与空模型根两个错误边界）
- 明确的工具限制（已写进测试本身）：Linux 上 `flutter test`/`flutter run` 把测试跑在 `flutter_tester` 里（`WP17_I4_PROCESS executable=.../flutter_tester`），所以 `Platform.resolvedExecutable` 是测试器而不是 bundle 可执行文件，产品那条“可执行文件相对”的默认库查找在 Linux 测试里无法被直接触发。测试因此在 Linux 上断言默认布局（`resolveOcrLibraryPath()` 必须以 `/lib/libmatrixflow_ocr.so` 结尾），并显式加载 `build/linux/x64/profile/bundle/lib/libmatrixflow_ocr.so`——也就是 Flutter 真的装进 bundle 的那一份。Windows 侧的 `flutter drive -d windows` 是真的跑 bundle 可执行文件，产品解析路径在那一边完整走通。

本轮修正的真实打包缺陷（`linux/CMakeLists.txt`）：原先 `install(TARGETS matrixflow_ocr ...)` 声明在 bundle 前缀解析之前，生成脚本把 `/usr/local/lib` 写死，`flutter build linux` 因而尝试写系统目录（首次实测：`file INSTALL cannot copy ... to "/usr/local/lib/libmatrixflow_ocr.so": Permission denied`）；改为在“清空 bundle”之后用生成的安装脚本复制，前缀退化（`CMAKE_INSTALL_PREFIX` 已经是 `/usr/local` 时不再有 `..._INITIALIZED_TO_DEFAULT`）也一并处理。

### 3.4 Android

APK（`flutter build apk --release --no-pub`，Gradle 用 `android/local.properties` 里的 `wp17OcrNcnnRoot`/`wp17OcrStbDir`，本机未提交）：成功，0，965.8s，`build\app\outputs\flutter-apk\app-release.apk` 54 804 251 字节，sha256 `b50e8ee728bac7fd43a6240c13413039f16aca4e444e90639a52255fc3e8c813`。

| APK 内库 | 字节 | sha256 | NEEDED |
|---|---|---|---|
| `lib/x86_64/libmatrixflow_ocr.so` | 5 390 440（与 I1 Release 一致） | `a31131981badfe3fca1a2829bf263c952cbb39f36dfa95e850d0bd1a61b954b1` | `liblog libandroid libjnigraphics libm libdl libc`（与 I1 记录一致） |
| `lib/arm64-v8a/libmatrixflow_ocr.so` | 6 482 512（与 I1 Release 一致） | `587cef511880caea0ae63b4b7bb4a0f8509aadf3b2415f2baa2613fdd5824c90` | 同上 |

`SONAME` 均为 `libmatrixflow_ocr.so`，`.note.android.ident`（`NT_ANDROID_TYPE_IDENT`）存在；Gradle 侧 `-DANDROID_PLATFORM=android-23`，两个库都在这台机的 API 23 与 API 36 设备上实际加载并执行（见下）。构建 APK 时 Kotlin 增量缓存的 `this and base files have different roots` 警告出现过（pub 缓存在 `C:`、工程在 `D:`），构建仍成功。

模拟器 `wp17r2api23`（`emulator-5554`，`ro.build.version.sdk=23`，`x86_64`）：

| 项 | 结果 |
|---|---|
| 设备侧 smoke（`native/ocr/tools/android_smoke.sh`，模型在 `/data/local/tmp/wp17i4-assets/ncnn`，12 张图在 `/data/local/tmp/wp17i4-evidence/images`） | `{"summary":{"images":12,"succeeded":12,"elapsed_ms":8962.5,"peak_rss_kb":437760}}`，exit 0；输出含中文/日文/英文行，与 Windows 基线逐行一致（例：`待办清单`、`买菜：西红柿、鸡蛋、牛奶`、`やること`、`To-do`） |
| 缺模型根 | `cannot read dict: /data/local/tmp/wp17i4-missing/ncnn/ppocrv5_dict.txt`，宽高 0、行空，exit 4 |
| 坏 PNG（`not a png`） | `PNG header decode failed`，exit 4 |

**Android 16 arm64 真机（Xiaomi `23117RK66C`，`ro.product.cpu.abi=arm64-v8a`，`ro.build.version.sdk=36`）**：同一天接入，本轮跑了同一份 arm64 `libmatrixflow_ocr.so`（独立构建，39 686 400 字节）与同一组 12 张图：

- `abi: arm64-v8a sdk: 36`
- `{"summary":{"images":12,"succeeded":12,"elapsed_ms":2820.2,"peak_rss_kb":320948}}`，exit 0
- 缺模型根 `cannot read dict: /data/local/tmp/wp17i4-missing/ncnn/ppocrv5_dict.txt`、坏 PNG `PNG header decode failed`，均按预期失败
- Release APK `adb install -r -t` 成功（`Success`，`primaryCpuAbi=arm64-v8a`），`monkey -p com.matrixflow.app` 启动后进程存活

诚实边界：arm64 这条证据是**同一份 native 库 + 同一组合成图**的真机运行，不是 Flutter SAF 选图流程在该机上的实测；APK 的 arm64 库加载只证明到“安装并启动、进程存活”，没有在真机上走 Dart 侧入口。API 23 x86_64 模拟器与 API 36 arm64 真机都不是“任意真机 OCR 质量”的结论。

### 3.5 定向回归与 analyze

| 命令 | 结果 / exit |
|---|---|
| `flutter analyze --no-pub` | **No issues found!**，0 |
| 16 个定向测试文件（I1/I3a/I3b/I4/RF02/RF11/UX02/OS21/OS27/platform_ui_policy），Release DLL + 部署模型 | **160 通过、0 失败**，日志 `01:06 +160: All tests passed!`，0（含 I1 的 5 项外部原生测试与 I4 的 9 项资源/布局测试） |
| `flutter build windows --no-pub`（未设 `WP17_OCR_*`） | 成功，且 bundle 内**没有** `matrixflow_ocr.dll`；默认构建继续可运行、不下载、不打包 OCR |

## 4. 代码改动与资源查找接线

- `lib/ocr/ocr_assets.dart`（新增）：把 `ncnn/` 五件套的文件名与可读性检查收敛到一处，`missingOcrModelFiles(root)` 返回缺失/空文件名单。`screenshot_capture.dart` 的 `_checkModels` 改为调用它，行为不变（仍是“缺少或不可读即 `ModelsMissing`，不下载、不上传”）。
- `lib/ocr/ocr_runtime.dart`：把私有的默认库路径改为公开的 `resolveOcrLibraryPath()`，逻辑与原来一致（Windows `<exe>\matrixflow_ocr.dll`、Linux `<exe>/lib/libmatrixflow_ocr.so`、Android `libmatrixflow_ocr.so`）。
- `lib/screenshot_import/screenshot_backend.dart`：资源根解析顺序固定为 **环境变量 `WP17_OCR_ASSETS` → 编译期 `--dart-define=WP17_OCR_ASSETS` → application support 下 `wp17r2-assets`**，环境与 support 目录都可注入以便断言；仍以 `assetsRoot/ncnn` 为唯一查找位置，缺失/不可读返回 `ModelsMissing`，DLL 或四个符号缺失返回 `NativeMissing`，都不自动下载、不访问网络。
- `windows/CMakeLists.txt` 未改（安装规则本来就写在可执行文件旁）；`linux/CMakeLists.txt` 只修安装时序与前缀退化，见 3.3；`native/ocr/CMakeLists.txt` 增加“独立构建时从 `WP17_OCR_NCNN_DIR`/`WP17_OCR_STB_DIR`/`WP17_OCR_NCNN_ROOT` 播种 cache”与 smoke 的 psapi 链接。
- `native/ocr/smoke.cpp`：只在测试工具里增加多图、耗时与峰值 RSS 汇总行；**C ABI 与识别算法未改**（`ocr_runtime.cpp` 未改）。

不属于本包：Android MainActivity/SAF、Windows/Linux runner 消息处理、`lib/main.dart`、Planner/导航/l10n、Store/SaveProtocol、截图提交与预览、公共路线图与发行脚本、`pubspec.yaml`/`pubspec.lock`（均未改）。

## 5. 可复现操作

```powershell
# 0) 依赖与模型（外部目录，不进仓库）
$env:WP17R2_ASSETS = "$env:LOCALAPPDATA\wp17r2-assets"
powershell -File tool/prepare_ocr_assets.ps1 -AssetRoot $env:WP17R2_ASSETS -DeployRoot "$env:LOCALAPPDATA\wp17i4-deploy"
powershell -File tool/prepare_ocr_assets.ps1 -AssetRoot $env:WP17R2_ASSETS -DeployRoot "$env:LOCALAPPDATA\wp17i4-deploy" -Check

# 1) Windows：Debug/Release 带 OCR 的 Flutter 构建
$env:WP17_OCR_NCNN_DIR = "$env:WP17R2_ASSETS\ncnn-build-win\install\lib\cmake\ncnn"
$env:WP17_OCR_STB_DIR   = "$env:WP17R2_ASSETS\third_party"
flutter build windows --release --no-pub
flutter build windows --debug   --no-pub

# 2) Windows：native 断言 + 真实 bundle 加载
$env:WP17_OCR_TEST_LIBRARY = "build\windows\x64\runner\Release\matrixflow_ocr.dll"
$env:WP17_OCR_TEST_ASSETS  = "$env:LOCALAPPDATA\wp17i4-deploy"
flutter test --no-pub test/wp17_i1_ocr_runtime_test.dart test/wp17_i4_assets_test.dart
$env:WP17_OCR_ASSETS = "$env:LOCALAPPDATA\wp17i4-deploy"
flutter drive --no-pub --dart-define=WP17_I4_BUNDLE=true --target=test/wp17_i4_bundle_ocr_test.dart --driver=test/wp17_i4_device_driver.dart -d windows

# 3) Linux（WSL2）：ncnn、bundle、真实加载
bash native/ocr/tools/build_ncnn_linux.sh
bash native/ocr/tools/build_linux_bundle.sh
bash native/ocr/tools/run_linux_bundle_test.sh

# 4) Android：APK 与两个 ABI 的 ELF 事实
powershell -File tool/build_ocr_android.ps1
# android/local.properties 增加：
#   wp17OcrNcnnRoot=...\wp17r2-assets
#   wp17OcrStbDir=...\wp17r2-assets\third_party
flutter build apk --release --no-pub
# 设备侧（模型与合成图需 push 到 /data/local/tmp）
adb -s <serial> shell sh /data/local/tmp/android_smoke.sh
```

## 6. 未关闭门禁

1. **转换权重的再分发授权**：当前唯一验证过的权重（nihui）没有授权声明。官方权重路线（Hugging Face Apache-2.0）已完成输入固定与脚本化，但本机 Paddle2ONNX 的 PIR 转换链路不可用（见 §1），产物哈希未产生。**发布阻塞未解除**，OCR 仍不是正式产品支持。
2. **官方权重未做算法一致性对照**：没有产物就无法把 12 张图的识别结果与现有基线对比；本轮三端识别用的仍是 nihui 权重。
3. **Windows 仍只有 Release `/MD` 的 ncnn**：Debug 通过 `/MD` + `_ITERATOR_DEBUG_LEVEL=0` 复用 Release ncnn，不是独立的 Debug ncnn 运行库。
4. **真机范围**：arm64 真机只在 `/data/local/tmp` 直接跑 native 库，没有走 Flutter SAF 选图与整机入口；Android API 23 x86_64 模拟器与 API 36 真机都不能替代“任意真机识别质量/性能”。
5. **Linux**：release/profile bundle 已在 Xvfb 下实际加载识别；没有显示器会话下的 GTK 界面实测，发行侧仍不产出 Linux 安装包（保持既有发行边界）。
6. **性能**：只记录本机实测耗时与峰值 RSS，没有低端机门槛、没有 Vulkan/GPU 路径、没有并发或长时间稳定性测量。
7. 集成端统一的**全量 Flutter 测试与云端验收**未跑（本包只跑定向回归与 analyze）。

## 集成修正（2026-10-01）

- bundle 设备测试改为显式 `WP17_I4_BUNDLE=true` 启用；默认测试不调用原生插件。上文平台证据保持原始运行范围，Linux 脚本改用 `xvfb-run -a`，只清理本次显示服务。
- 转换 `--check` 不下载、不改锁；未固定的输入拒绝使用。输出先校验再复制。部署脚本先验证四份官方产物再安装到 `ncnn/`，转发离线和解释器参数；缺少产物锁仍明确退出 3，不绕过官方转换阻塞。
- 准备 `-Check` 不创建目录、不删除工作区，并校验部署副本摘要；坏产物不覆盖已有验证模型。`python -m unittest discover -s native/ocr/tools -p test_ocr_preparation.py` 在 Windows 本地 **7 项通过，exit 0**；Linux CI 仅执行三项 Python 只读检查，PowerShell 部署四项不冒充 Linux 验收。
