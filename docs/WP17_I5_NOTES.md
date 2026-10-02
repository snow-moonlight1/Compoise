# WP17-I5：官方 OCR 模型转换与部署

日期：2026-10-02–03。官方六个输入的原有摘要全部保持；PIR → ONNX → ncnn 已实际完成，并经两个全新转换目录逐字节复现。官方产物已在 Windows / Linux 的同一份 C++ runtime 上通过原 R2 的文字、几何、重复会话和错误边界对照。**I4 的官方转换技术阻塞已关闭；正式发行、Android 官方模型设备流程和真实截图质量门禁仍未关闭。**

基线 `39cf8ed6df7f5290a9b45c970f9c5e279c89230a`；分支 `codex/wp17-i5`；由 Codex 创建的独立工作树 `C:\Users\20214\.codex\worktrees\wp17-i5\martix`；提交身份 `wp17-i5-agent <wp17-i5-agent@local.invalid>`。完整提交 SHA 由交接消息提供，不在本文自引用。只提交本工作树，没有 amend / push / 修改 main，没有调用其他 Agent、ADB 或真实 Compoise 窗口。

## 输入、工具链与来源

两个官方模型卡声明 Apache-2.0；原 I4 的六个 `inference.json / inference.pdiparams / inference.yml` 均重新下载并逐文件验证。现在还固定了 Hugging Face revision：

| 官方仓库 | 不可变 revision |
|---|---|
| `PaddlePaddle/PP-OCRv5_mobile_det` | `0d63e78e2b680928f6b1747d76a08db6e645efb7` |
| `PaddlePaddle/PP-OCRv5_mobile_rec` | `682f20538d8c086cb2128e5cfac775e6c4904e85` |

六个输入的完整 SHA-256、大小和 `/resolve/<revision>/...` 来源在 `native/ocr/tools/models.lock.json`。没有将上游变化后的摘要当成旧锁；本次没有发现输入变化。模型卡原文与许可证存于 `native/ocr/licenses/`。

转换环境是 WSL2 Ubuntu 24.04、Linux x86_64 / glibc 2.39、CPython **3.12.3**，专属 venv `/home/ubuntu/wp17i5-tools`；Linux 原生构建工具为 CMake **3.28.3** / Ninja **1.11.1**。关键包是 **Paddle 3.0.0、Paddle2ONNX 2.1.0、ONNX 1.17.0、onnxoptimizer 0.4.2、pnnx 20260526、NumPy 1.26.4、protobuf 3.20.2、setuptools 75.8.0、packaging 24.2**。实际全部 **22 个包**的版本、官方 PyPI wheel URL / SHA-256 已由安装报告固定于 `conversion_toolchain.lock.json`；`requirements-convert.txt` 带每个 wheel 的摘要。脚本核对全部版本，并核对 native pnnx 的固定摘要：

`c3555c48e054245e50fa434a7673fbdad2b8f8c6cdca8c1579601f9882f474a0`。

pnnx 直接运行该 wheel 中的原生可执行文件，不导入需要 PyTorch 的 Python 包装层。venv、wheel、模型、原生库与日志均在外部私有目录；Linux 原生链接只读复用 I4 的固定 ncnn 安装树，Windows 将固定 SDK 复制到本包私有目录。没有共享写入旧包资产。

官方依据：[Paddle2ONNX](https://github.com/PaddlePaddle/Paddle2ONNX/tree/develop)文档说明 Paddle 3.0 与 `.json/.pdiparams` 导出；[PaddleX 插件文档](https://paddlepaddle.github.io/PaddleX/3.0/en/pipeline_deploy/paddle2onnx.html)说明其底层也是 Paddle2ONNX；[ncnn 转换文档](https://github.com/Tencent/ncnn/blob/master/docs/how-to-use-and-FAQ/use-ncnn-with-pytorch-or-onnx.md)及 [PP-OCRv5 示例](https://github.com/Tencent/ncnn/blob/master/examples/ppocrv5.cpp)给出 ONNX → pnnx 的多形状路线。本包直接调用已验证的 Paddle2ONNX CLI，没有把 I4 的 1.3.1 或 Windows rc 插件失败写成成功记录。

隔离安装的真实失败及修复：系统缺 ensurepip，`python3 -m venv` 退出 1，但已建立 venv 解释器；从 `https://bootstrap.pypa.io/get-pip.py` 安装私有 pip 后继续。onnxoptimizer 0.3.13 无 cp312 wheel，源码构建缺 Python 开发头文件，退出 1；换为官方 0.4.2 wheel。Paddle / 独立 Paddle2ONNX CLI 分别缺 setuptools / packaging，导入退出 1；仅在本 venv 补齐固定版本后成功。没有修全局 Windows Python。

## 固定命令、输出与复现

最终安装/转换命令在 WSL Bash 中执行（工作树、缓存都使用实际路径）：

```bash
/home/ubuntu/wp17i5-tools/bin/python -m pip install --require-hashes --no-deps \
  -r /mnt/c/Users/20214/.codex/worktrees/wp17-i5/martix/native/ocr/tools/requirements-convert.txt
/home/ubuntu/wp17i5-tools/bin/python \
  /mnt/c/Users/20214/.codex/worktrees/wp17-i5/martix/native/ocr/tools/convert_models.py \
  --assets /home/ubuntu/wp17i5-private/assets --offline --record-outputs
```

均退出 **0**。首次明确使用 `--record-outputs` 后，脚本对两模型分别在 `replay-*/a`、`replay-*/b` 导出，全部匹配才记录新锁。随后最终脚本、另一份全新联网缓存也重新执行了独立转换，六份输出均匹配同一锁。普通转换不会记锁，缺输出锁仍退出 **3**，任何既有固定摘要不符均拒绝。没有复用来历不明的旧 ONNX。

实际每模型的完整 CLI 模板如下，`<model>` 取 `det/rec`、`<scratch>` 每轮独立，所有输入先过锁：

```bash
/home/ubuntu/wp17i5-tools/bin/python -c 'from paddle2onnx.command import main; main()' \
  --model_dir /home/ubuntu/wp17i5-private/assets/convert-work/paddle/PP-OCRv5_mobile_<model> \
  --model_filename inference.json --params_filename inference.pdiparams \
  --save_file <scratch>/PP_OCRv5_mobile_<model>.onnx \
  --opset_version 11 --enable_onnx_checker True \
  --enable_auto_update_opset False --optimize_tool onnxoptimizer
/home/ubuntu/wp17i5-tools/lib/python3.12/site-packages/pnnx/pnnx \
  <scratch>/PP_OCRv5_mobile_det.onnx inputshape=[1,3,320,320] \
  inputshape2=[1,3,256,256] fp16=1 optlevel=2
/home/ubuntu/wp17i5-tools/lib/python3.12/site-packages/pnnx/pnnx \
  <scratch>/PP_OCRv5_mobile_rec.onnx inputshape=[1,3,48,160] \
  inputshape2=[1,3,48,256] fp16=1 optlevel=2
```

上述命令全部退出 **0**，另执行 `onnx.checker.check_model` 并检查单输入/单输出，实际 opset **11**，ncnn 入口/出口为 `in0/out0`，检测高宽及识别宽度保持动态。未启用自动 opset 升级。完整参数和实际平台/包版本亦写入锁。

| 产物（共同前缀 `PP_OCRv5_mobile_`） | 字节 | SHA-256 |
|---|---:|---|
| `det.onnx` | 4,767,934 | `d4aa24d408cd70b8b9f66cc758e20f397fc31a9c69d8477cf8887fc53bd5fceb` |
| `rec.onnx` | 16,537,720 | `dc7de8ee31d9246783cf346f3b207b4cb871e11824b1cfab2ff20aa1f1f8e67b` |
| `det.ncnn.param` | 24,256 | `19359eea27e9f38b493a40ac11acbb95bbe6cbe174866e9e043cbe6a786f3ce6` |
| `det.ncnn.bin` | 2,357,216 | `857a96bc963725105b78a178dfcc3c0c3db1a7b9eef32244367b2cb105ccf60b` |
| `rec.ncnn.param` | 19,632 | `dbd3a743febb5d08157059d4ae31f9372b413b9739ef9d5963da68c987a2481c` |
| `rec.ncnn.bin` | 8,242,276 | `49d9907a55ba20fa6637f9f788f66ab00793bc8ce57a733a09dbe86b9a2e3db0` |

四个 ncnn 文件加 74,012 字节的既有字典共 **10,717,392 字节**。两份 bin 碰巧与历史 nihui bin 字节相同，param 摘要不同；本次 provenance 是官方输入的实际转换，不是给 nihui 成品补授权。转换只在 Linux 验证，未宣称 Windows 转换器可用。

## 部署与失败保护

Linux 对应入口 `prepare_ocr_assets.py` 与 PowerShell 官方路线共用 `publish_models.py`。先核对整套权重、字典及许可附件，全部复制到暂存目录并核验，再以整目录替换 `<AssetRoot>/ncnn` 与部署根；复制失败不修改目标，目录替换失败回滚。部署期间应关闭本组件的 OCR 会话；异常进程终止后的重试需要重新运行准备命令，本包没有验证断电恢复。

部署根包含 `ncnn/` 五件套、`licenses/` 五份锁定上游附件和本项目 notice、`deployed.json` 的六输入来源/摘要、ONNX 摘要、转换工具链与权重摘要。既有 nihui 权重不作为官方路线输入。默认构建仍不含 OCR 模型或库；准备脚本的历史 `nihui` 默认值保持，必须显式选择官方来源。

实际从**全新 Linux 缓存**完成下载、转换、部署，退出 **0**：

```bash
/home/ubuntu/wp17i5-tools/bin/python \
  /mnt/c/Users/20214/.codex/worktrees/wp17-i5/martix/native/ocr/tools/prepare_ocr_assets.py \
  --assets /home/ubuntu/wp17i5-private/empty-online-assets \
  --deploy /home/ubuntu/wp17i5-private/empty-online-deploy \
  --python /home/ubuntu/wp17i5-tools/bin/python
```

Windows 将上述受控的四份产物复制到自己的空模型缓存，再运行：

```powershell
powershell -NoProfile -File tool/prepare_ocr_assets.ps1 `
  -AssetRoot C:\Users\20214\AppData\Local\wp17i5-private\assets `
  -DeployRoot C:\Users\20214\AppData\Local\wp17i5-private\deploy-win `
  -ModelSource official -Ncnn none -SkipNcnnSource
```

退出 **0**。这证明 Windows 官方产物缓存部署；Windows 从零运行 PIR 转换没有验收。Linux bundle 准备脚本增加 `WP17_MODEL_SOURCE=official`，调用同一离线验证/发布入口；本包只检查该构建脚本语法，没有重建 Flutter Linux bundle。

`validate_official_preparation.py` 在两个平台的实际私有缓存上运行；Windows 加 `--powershell`，Linux 使用 Python 入口。`--assets/--deploy/--report` 指向本包私有路径。最终均退出 **0**，内含以下真实 CLI 断言：

| 场景 | Windows / Linux 实际退出码与结果 |
|---|---|
| 已缓存离线准备 | **0**，完整复用并部署 |
| 准备 `-Check / --check` | **0**，全部缓存、部署文件及锁的 SHA-256 和 `st_mtime_ns` 前后相同 |
| 转换 `--check` | **0**，六输入、两 ONNX、四 ncnn 输出验证，字节/mtime 不变 |
| 官方输入翻转一字节 | **3**，锁和既有部署字节/mtime 不变 |
| 官方输出翻转一字节 | **3**，锁和既有部署字节/mtime 不变 |
| 恢复私有验证副本后重试 | **0** |
| 空缓存 + 离线 | **4**，未生成部署目录 |

回归另覆盖两个独立转换结果不同、已有输出锁不符、实际工具版本不符/解释器缺失、坏许可附件、复制失败、第二个目录改名失败后的回滚及重试。缺工具退出 **5**，用法错误退出 **2**，离线子转换的退出码不会被准备入口改成校验错误。PowerShell 从 Python/PowerShell 7 调用时显式加载自身内置 Utility 模块，修复实测出现过的 `Get-FileHash` 模块发现失败。`--check` 禁止自动生成本项目 Python 字节码缓存。

## 原生识别与资源实测

`ocr_runtime.cpp`、C ABI、Dart 导入业务、R2 黄金结果均未修改。ncnn 固定 `c6b351b56fbe32e0381ae00331e3df649b20d7b7`，CPU、Vulkan OFF。Windows 使用 VS 2022 17.14、Release `/MD`；Linux 使用 Clang **18.1.3**，同一 `native/ocr/CMakeLists.txt` 独立构建。两端仅运行 DLL/SO 和独立 smoke/ctypes 调用，不开产品窗口或设备 bundle。

| 原生库 | 字节 | SHA-256 |
|---|---:|---|
| Windows `matrixflow_ocr.dll` | 14,126,592 | `e21bf6832f701fd3fbc3c1919a7a05525836f47bf1b78e6e23a7f35b84bdbfc1` |
| Linux `libmatrixflow_ocr.so` | 16,940,360 | `e35b54ed487797ace9c45aec1d6e279ca18602cc75deccbbb26ca311dfae02db` |

实际构建命令：`powershell -File tool/build_ocr_windows.ps1 -Assets <本包私有资产> -Out <本包私有 native-win>`；Linux `cmake -S <工作树>/native/ocr -B /home/ubuntu/wp17i5-private/native-linux -G Ninja -DCMAKE_BUILD_TYPE=Release -Dncnn_DIR=/home/ubuntu/wp17i4-ncnn-linux/install/lib/cmake/ncnn -DWP17_STB_DIR=/home/ubuntu/wp17i5-private/assets/third_party -DWP17_OCR_BUILD_SMOKE=ON`，再 `cmake --build ... --parallel 4`。两端构建均 **0**。

`validate_official_runtime.py --library <DLL/SO> --assets <官方部署根> --report <私有 JSON>` 在每平台使用 **4 线程**，同一会话连跑 3 个完整批次，再重建 2 次会话各跑一批，共 **60 次识别**。两平台命令均 **0**：12 图的 **274 行文字全部匹配**，相对原 R2 矩形的最大分量差 **0**；五批的完整 JSON 结果也完全一致。

| 平台 | 五批分别耗时（ms） | 五批进程峰值 RSS（KiB） |
|---|---|---|
| Windows | 5108.3、7722.0、26935.7、57774.5、32313.5 | 469768、469984、470056、470260、470260 |
| Linux | 12228.2、12688.8、12236.1、11862.8、11184.6 | 472804、472972、472972、483268、483268 |

Linux 单独 smoke 12 图：**12 成功**、8206.0 ms、峰值 473548 KiB，退出 **0**。这些是本机与其他任务并行时的测量，不是低端设备性能门槛；会话重建后的峰值有增长，五批不能代表长时间泄漏验收。

两平台均验证八项错误边界：缺图；坏 PNG；空文件；超过 16 MiB；宽 4097；高 8193；4000×3200 超像素限制；缺模型字典。返回原有明确错误，尺寸拒绝时宽为 0，行为空。新验证工具起初用不完整 PNG 头测试尺寸，被正确拒绝为坏 PNG，退出 1；改为流式生成完整有效 PNG 后，两端通过。没有修改算法或黄金结果掩盖该夹具错误。

固定 ncnn 会输出 `Convolution 1d input compatibility path is deprecated`，来源是当前导出图使用其现有兼容分支；当前加载与对照均通过。本包保留原图和固定 ncnn，没有擅自改层类型。后续升级 ncnn/pnnx 必须重新转换、锁定和对照，不能据此假定新版本仍兼容。

## 回归、许可与剩余门禁

| 命令 | 结果 / exit |
|---|---|
| `python -m unittest discover -s native/ocr/tools -p test_ocr_preparation.py`，Windows | **16 通过，0** |
| 同命令，Linux | **11 通过 / 5 Windows 专属跳过，0**；这些 skip 不作为原生识别证据 |
| Flutter 3.32.8 `flutter analyze --no-pub` | **No issues found，0** |
| `flutter test --no-pub test/wp17_i1_ocr_runtime_test.dart test/wp17_i3a_native_capture_test.dart test/wp17_i4_assets_test.dart` | 显式官方模型和本包 DLL，**16 通过，0**；含 12 图文字/几何及 128 草稿对照 |
| 未设置 OCR 环境变量的 `flutter test --no-pub` | **1376 通过 / 7 跳过，0**；未启用设备 bundle，无 OCR 工具/模型不阻断默认测试 |
| 两个 Linux OCR 构建脚本 `bash -n` | **0**；不是 bundle 构建证据 |

Flutter 固定 `D:\Dev_SDKs\Flutter_3.32.8`。本工作树复用同一 `pubspec.lock` 对应的现有 package_config，未运行依赖升级，pubspec 与锁未修改。设备 bundle 测试仍须显式 `WP17_I4_BUNDLE=true`；本轮没有执行它。

`THIRD_PARTY_OCR_NOTICES.md` 和附件保留 Apache-2.0、stb MIT/Unlicense、完整 ncnn BSD/zlib/MIT 文本及官方模型卡。许可文件的 URL、大小、摘要在模型锁；ncnn LF 文件摘要与 I4 Windows CRLF 摘要不同，已验证只差换行，内容相同。Git 属性保持所附许可证 LF 字节。任何后来获准的 OCR 分发须保留部署内整个许可目录、notice 与 provenance。转换依赖是私有构建工具，不随应用分发；Windows MSVC/OpenMP 及 Linux 系统运行库的发行包装仍由后续发行包处理。

仍待完成：Android 官方权重的完整设备流程；真实截图与多设备质量；低端机/长时间资源负担；官方模型 Flutter bundle 的本轮重新验收；正式发行授权与最终包装。没有把历史 Android arm64 证据、本包合成图成绩或无 OCR 的默认测试描述成真实截图端到端支持。本包不打 tag、不发 Release。公共 ROADMAP/README/发行状态、平台 runner、MainActivity、Store/SaveProtocol、凭据均未改。
