# WP17-I1：离线 OCR 运行时

状态：同一份 ncnn + PP-OCRv5 mobile CPU 运行时已在 Windows、WSL2 Linux 和 Android API 23 上实际编译并对照 R2 合成截图。转换后的模型权重再分发许可没有核清，本包不是正式发行能力。图片选择、草稿校对和任务库接线仍不在本轮。没有接 Store、文件选择器、`lib/import_preview` 或全局导航。

样本只用 `docs/evidence/wp17r2/samples/images`。对照基准是 `docs/evidence/wp17r2/results/win/raw/ncnn-cpu-t4/all.json`：文字完全一致，矩形每个分量绝对差不超过 1，宽高一致，成功时 `error` 为空。

## 构建方式

模型、字典、ncnn 和 `stb_image.h` 都不进仓库。Windows/Linux 仍用 `WP17_OCR_NCNN_DIR` 与 `WP17_OCR_STB_DIR`。Android 用 Gradle 属性 `wp17OcrNcnnRoot`、`wp17OcrStbDir`，或同名的 `android/local.properties` 键。`flutter build apk` 启动 Gradle 时只保留 `JAVA_HOME` 和 `PATH`，`ORG_GRADLE_PROJECT_*` 到不了构建，所以本轮增加了 `local.properties` 这条通道。未提供外部依赖时，普通 Flutter 构建不下载、不打包 OCR。

启用后的 Android 只打 `x86_64` 和 `arm64-v8a`，STL 用 `c++_static`，与现有 ncnn 预编译树一致。应用 `minSdk` 是 23，`ndkVersion` 是 `28.0.12433566`。

Windows 上这份目录是 Flutter 子目录时不再调用 `project()`，安装前缀留在可执行文件旁边。Debug 使用 `/MD` 和 `_ITERATOR_DEBUG_LEVEL=0`，因为手头只有 Release `/MD` 的 `ncnn.lib`。Android 上从 ncnn 的接口选项里去掉 `-fno-exceptions`，本目标再编译 `-fexceptions`，这样 C ABI 的 `try/catch` 能在失败时返回 JSON。

## 本轮实测

`flutter analyze --no-pub`：No issues found。

`flutter test --no-pub test/wp17_i1_ocr_runtime_test.dart`：5 项通过。其中 3 项原生测试在设置 `WP17_OCR_TEST_LIBRARY`（Flutter Release 的 `matrixflow_ocr.dll`）和 `WP17_OCR_TEST_ASSETS` 后实际加载了库，覆盖 12 张 R2 图、缺字典、坏 PNG、空文件、超宽图、重复调用和取消。未设置这两个变量时，这 3 项仍然 skip，无库的 CI 可以过。

### Windows

Flutter 3.32.8。Debug 与 Release 的 `matrixflow_ocr.dll` 都在 `compoise.exe` 旁边：

- Debug：`matrixflow_ocr.dll` 20981760 字节，`compoise.exe` 1247744 字节。
- Release：`matrixflow_ocr.dll` 14126592 字节，`compoise.exe` 247296 字节。

这两份安装库的 12 张图都对照通过。同一会话再跑一张结果相同；销毁后重建会话，结果仍相同。`mf_ocr_free(nullptr)` 调用后进程正常退出。缺模型目录时 `mf_ocr_create` 仍返回会话，识别错误是 `cannot read dict`。

错误返回：缺文件 `cannot open image`；空文件和超过 16 MiB 都是 `image file exceeds 16 MiB or is empty`；坏 PNG 头 `PNG header decode failed`；宽 4097、高 8193、以及 4000×3200（超过 12×1024×1024 像素）都是 `image dimensions exceed OCR limit`，宽高为 0，行列表为空。

独立 Release DLL 上，`batch_of_10` 的工作集峰值：一个会话连跑，从 19396 KB 到 470932 KB；每张图创建并销毁会话，从 19324 KB 到 370956 KB。按张重建会话没有把峰值抬到十张图相加的量级。

### Linux / WSL2

Ubuntu 24.04，clang/clang++ 18。系统没有 g++，OpenMP 也没有找到；库仍然链接并完成推理。`ldd` 只看到 `libstdc++`、`libm`、`libgcc_s`、`libc`。

Release 与 Debug 的 `libmatrixflow_ocr.so` 都跑完 12 张，失败列表为空，重复调用一致。缺文件是 `cannot open image`，缺字典是 `cannot read dict`。批次后 VmHWM：Release 492332 KB，Debug 492580 KB。

WSL 里没有 Flutter SDK，没有执行 `flutter build linux`。`linux/CMakeLists.txt` 把库装到 bundle 的 `lib/` 这条规则没有被 Flutter 打包跑过。Linux 库是在后面的 CMake 修正之前编出的，`ocr_runtime.cpp` 之后没有再改；clang 默认开启异常。

### Android API 23

Debug APK 含有：

- `lib/x86_64/libmatrixflow_ocr.so` 5851760 字节
- `lib/arm64-v8a/libmatrixflow_ocr.so` 6636120 字节

Release APK 含有剥离后的同名库，5390440 与 6482512 字节。AGP 的 release 原生构建类型是 RelWithDebInfo。两边的 ELF note 都是 API 23（`0x17`）和 NDK `r28-beta1` / `12433566`。`NEEDED` 只有 `liblog`、`libandroid`、`libjnigraphics`、`libm`、`libdl`、`libc`。

模拟器 `wp17r2api23`（`emulator-5554`，`ro.build.version.sdk=23`，`x86_64`）加载了 Debug APK 的 x86_64 库，以及与 Release APK 字节相同的剥离库。两份都是 12 张对照通过。缺文件 `cannot open image`，缺字典 `cannot read dict: /data/local/tmp/wp17i1-missing/ncnn/ppocrv5_dict.txt`，宽高为 0。

arm64-v8a 真机加载和识别：未验证。当时 `adb devices` 只有这个 x86_64 模拟器。

第一次 `flutter build apk --release` 在 Kotlin 增量缓存关闭时把 Gradle daemon 打崩（pub 缓存在 `C:`，工程在 `D:`）。当时两个 ABI 的 release 库已经链出来。清掉该缓存并用进程内 Kotlin 编译后，release APK 打成，库字节与已在模拟器上跑过的剥离库一致。这个 Kotlin 开关没有留在仓库里。

## 依赖来源与许可

外部目录是本机的 `wp17r2-assets`，哈希与 `docs/evidence/wp17r2/assets.lock.json` 一致。

| 文件 | sha256 | 来源与许可 |
| --- | --- | --- |
| `ncnn/ppocrv5_dict.txt`，74012 字节 | `d1979e9f794c464c0d2e0b70a7fe14dd978e9dc644c0e71f14158cdf8342af1b` | PaddleOCR 官方字典，Apache-2.0 |
| `third_party/stb_image.h` v2.30，283010 字节 | `594c2fe35d49488b4382dbfaec8f98366defca819d916ac95becf3e75f4200b3` | nothings/stb。文件头写 public domain；上游同时提供 MIT 或 Unlicense |
| ncnn `LICENSE.txt`，6513 字节，源码提交 `c6b351b56fbe32e0381ae00331e3df649b20d7b7` | `3a066e39806976fe274a042929523c68821c54bcf73369ed61aae2717edd54e8` | BSD-3-Clause |
| `PP_OCRv5_mobile_det.ncnn.bin`，2357216 字节 | `857a96bc963725105b78a178dfcc3c0c3db1a7b9eef32244367b2cb105ccf60b` | `nihui/ncnn-android-ppocrv5` 转换权重 |
| `PP_OCRv5_mobile_det.ncnn.param`，24821 字节 | `358f459680ae0e7a73e477469e529ce116f68c629019ec7a0b6457d2d9117934` | 同上 |
| `PP_OCRv5_mobile_rec.ncnn.bin`，8242276 字节 | `49d9907a55ba20fa6637f9f788f66ab00793bc8ce57a733a09dbe86b9a2e3db0` | 同上 |
| `PP_OCRv5_mobile_rec.ncnn.param`，20031 字节 | `f52a6586ac3338d8c350db0c9f3c55ff2ecd3763327f9bc7f0efc091f8a63e74` | 同上 |

`GET /repos/nihui/ncnn-android-ppocrv5/license` 返回 404。该仓库说明权重由官方 PaddleX PP-OCRv5 mobile 经 ONNX/pnnx 转出，这不是再分发授权。上游 PaddleOCR 为 Apache-2.0，不能据此把转换后的 bin/param 放进本仓库或标成可随应用分发。字典、stb 和 ncnn 源码可以按各自许可随附声明再分发。权重继续放在仓库外。

## 仍未关闭

- 转换权重的再分发许可。许可未核清，不能声称 OCR 已正式支持。
- arm64-v8a 真机加载和识别：未验证。
- WSL 上的 Flutter Linux bundle 没有构建。
- Windows Debug 链接的是 Release ncnn，不是单独的 Debug ncnn。
- I3 才把文件选择器的临时路径交给 `recognizeFiles`，转成 `wp17r2-draft/1`，并在用户校对确认后写 Store。原图和 OCR 中间数据不进任务库或日志。
