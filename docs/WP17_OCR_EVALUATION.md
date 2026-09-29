# WP17-R2：离线 OCR 选型实测

日期：2026-09-29。范围：只评估 ncnn + PP-OCRv5 mobile 与 Tesseract 5 + `tessdata_fast` 的截图文字识别及任务草稿解析；未接入产品代码。原始输出、逐图差异和生成的完整结果表见 [`evidence/wp17r2/results/tables.md`](evidence/wp17r2/results/tables.md)。本报告中的数字以该表及对应 `summary.json` 为准。

## 结论与平台状态

**WP17-I 的离线 OCR 首选 ncnn + PP-OCRv5 mobile CPU 配置**，再接可编辑、必须经用户确认的任务草稿。Windows 12 张合成截图上，4 线程配置文字 CER 0.0220，128/128 个 GT 任务命中，误提取任务 0，12/12 张任务阅读顺序一致；同组 Tesseract 三语 PSM 3 的 CER 为 0.2162，任务召回 0.844，误提取 8。ncnn 单张中位耗时 481 ms，10 张批处理 5005 ms，峰值 449 MiB；这些资源占用仍需在真实低端设备上评估。Tesseract 的峰值约 207 MiB，存在内存优势。`ncnn-reccap320` 用速度换准确率（CER 0.0785），不宜作为默认配置。

| 平台 | ncnn 状态 | Tesseract 状态 | 可得出的结论 |
|---|---|---|---|
| Windows x64 | 6 配置中的 3 组完成 12/6 张实测、评分 | 3 组完成 12/6 张实测、评分 | 有可比较的本机 CPU 结果 |
| Linux / WSL2 Ubuntu 24.04 | 同一模型与 CLI 已运行、评分；三组 ncnn CER 与 Windows 一致 | 已运行、评分，wheel 中的 5.5.1 与 Windows 5.4.0 版本不同 | 可比较识别质量；WSL2 耗时不可直接当作 Linux 裸机性能 |
| Android API 23 x86_64 模拟器 | 关闭 x86 SIMD 后，12 张全部识别并按相同代码评分；原构建在推理时 SIGILL | 未构建、未运行 | 模拟器验证了运行和结果一致性，不提供真机性能结论 |
| Android arm64-v8a | NDK r27b 交叉编译通过，未在真机运行 | 未构建、未运行 | 只有构建兼容性证据，没有运行或性能结论 |

Android 端尚不能据此宣称正式支持。原 SIGILL 的根因是模拟器 guest CPU 只暴露 SSE4.2，而原 ncnn x86_64 构建启用了 AVX/AVX2/FMA/F16C。关闭这些选项后的 x86_64 二进制完成了 12 张运行与评分；模拟器耗时不能代替真机性能。Tesseract Android 端未尝试构建，原因是本轮先完成共享核心在 API 23 的 ncnn 冒烟及桌面对照；其原生依赖、Leptonica 和语言包打包仍需另行验证。

## 输入、配置及评分口径

样例是 [`evidence/wp17r2/samples/`](evidence/wp17r2/samples/) 中 12 张自绘待办截图，无私人数据。逐行真值位于 `samples/labels.json`，含文本、行框、角色、任务键、缩进、勾选态。覆盖中英日、明暗主题、字号 ×0.8、缩放 ×0.75/×1.5、长滚动拼接、重复图片、已勾选复选框与子任务。`batch_of_10` 是固定的 10 张批次。主配置用全部 12 张；单线程、rec 宽度上限 320、PSM 6 用固定 6 张子集，不能直接拿任务总数与主配置相比。Tesseract 的 `oracle-lang` 按标注语言选择单一语言，真实导入流程没有该先验信息，只作上界对照。

两引擎使用同一个 `core/wp17r2_ocr.cpp` 的图像解码、预处理和输出格式；文字层由 `score_text.py` 用逐行匹配后的编辑距离评分，结构层由 `adapter.py` 生成草稿、`score_structure.py` 独立评分。CER 是字符错误率，`micro` 汇总字符计数，`macro` 对图片取平均。文字误检行与草稿误提取任务是不同指标：例如 Windows ncnn 4 线程的原始 OCR 误检 48 行（多为复选框或状态图标），经几何过滤后误提取任务为 0。阅读顺序指标只衡量**命中任务**的顺序，不能掩盖漏检。

完整结果直接见[自动生成的 A–F 表](evidence/wp17r2/results/tables.md)：A 为冷启动、批处理及峰值内存，B 为文字层，C/C2 为草稿结构、阅读顺序及待确认项，D/E 为逐图结果，F 为资产与二进制体积。表由 `tools/report_tables.py` 从三个平台的 `summary.json` 和本地资产重新生成，不另维护手抄表。

Windows 与 Android 模拟器的 ncnn 主配置勾选态和父级判断均为 1.000，截止时间正确率 0.944；12 张的命中任务顺序均一致。Android 与 Windows/Linux 的 ncnn CER 均为 0.0220，三平台识别结果一致。PP-OCRv5 mobile det+rec 参数/权重加字典合计约 10.2 MiB；Android x86_64 关闭 SIMD 后的 CLI 剥离体积约 4.70 MiB，arm64-v8a CLI 剥离体积约 5.72 MiB，详见生成表 F。CLI 大小不是 APK 增量，尚未测 Flutter/ABI 打包后的体积。

## 可复现路径

在仓库根目录执行以下 PowerShell 命令。模型、语言包、ncnn 源码和第三方头文件位于仓库外的 `$env:LOCALAPPDATA\wp17r2-assets`；下载源与 SHA-256 见 [`assets.lock.json`](evidence/wp17r2/assets.lock.json)，应先用 `tools/fetch_assets.py` 准备并校验文件。ncnn 是 `1.0.20260929`、源码 commit `c6b351b56fbe32e0381ae00331e3df649b20d7b7`；模型为 PP-OCRv5 mobile det+rec 的 ncnn 转换件。Windows Tesseract 为 5.4.0.20240606，Linux wheel 带 5.5.1；语言包为锁定 SHA-256 的 `tessdata_fast` `chi_sim/eng/jpn`。这些 URL 多数指向上游 `main/master`，未来重新下载时必须比对锁文件哈希。

```powershell
$r2 = (Resolve-Path docs\evidence\wp17r2).Path
$assets = Join-Path $env:LOCALAPPDATA 'wp17r2-assets'
Set-Location $r2
python tools\fetch_assets.py  # 下载缺失资产，并核对已有锁定文件的 SHA-256
if (-not (Test-Path "$assets\ncnn-src\.git")) { git clone https://github.com/Tencent/ncnn.git "$assets\ncnn-src" }
git -C "$assets\ncnn-src" checkout c6b351b56fbe32e0381ae00331e3df649b20d7b7
```

Windows 构建与重跑（`<MSVC>` 替换为 VS2022 工具目录；运行时 Tesseract DLL 所在目录须在 PATH）：

```powershell
# 首次使用时运行已下载的 Tesseract 安装程序；语言数据由 assets/tessdata_fast 提供。
if (-not (Test-Path 'C:\Program Files\Tesseract-OCR\libtesseract-5.dll')) {
  Start-Process -FilePath "$assets\installer\tesseract-ocr-w64-setup.exe" -Wait
}
cmake -S "$assets\ncnn-src" -B "$assets\ncnn-build-win" -G 'Visual Studio 17 2022' -A x64 `
  -DCMAKE_INSTALL_PREFIX="$assets\ncnn-build-win\install" `
  -DNCNN_VULKAN=OFF -DNCNN_OPENMP=ON -DNCNN_PIXEL=ON `
  -DNCNN_BUILD_EXAMPLES=OFF -DNCNN_BUILD_TOOLS=OFF -DNCNN_BUILD_TESTS=OFF
cmake --build "$assets\ncnn-build-win" --config Release --target install
python core\make_tess_implib.py --dll 'C:/Program Files/Tesseract-OCR/libtesseract-5.dll' `
  --dumpbin '<MSVC>/bin/Hostx64/x64/dumpbin.exe' --lib '<MSVC>/bin/Hostx64/x64/lib.exe' `
  --out "$assets\tess-implib"
cmake -S core -B "$assets\build-win" -G 'Visual Studio 17 2022' -A x64 `
  -Dncnn_DIR="$assets\ncnn-build-win\install\lib\cmake\ncnn" `
  -DWP17R2_THIRD_PARTY="$assets\third_party" `
  -DWP17R2_TESSERACT_LIB="$assets\tess-implib\tesseract.lib"
cmake --build "$assets\build-win" --config Release
$env:PATH = 'C:\Program Files\Tesseract-OCR;' + $env:PATH
Set-Location tools
python run_bench.py --platform win --cli "$assets\build-win\Release\wp17r2_ocr.exe" --assets $assets
python report_tables.py
Set-Location ..
```

Linux 为 WSL2 Ubuntu 24.04；`build_linux.sh` 在 `~/wp17r2` 从已校验 Windows 资产复制模型，并使用 `tesserocr==2.11.0` 的 CPython 3.12 manylinux x86_64 wheel 自带 Tesseract/Leptonica 共享库，无需 sudo。性能采样使用 WSL 文件系统的样例副本。

```powershell
New-Item -ItemType Directory -Force "$assets\tessocr-wheel" | Out-Null
python -m pip download tesserocr==2.11.0 --only-binary=:all: --no-deps `
  --platform manylinux_2_28_x86_64 --python-version 312 --implementation cp --abi cp312 `
  -d "$assets\tessocr-wheel"
$wslR2 = (wsl -d Ubuntu-24.04 -- wslpath -a $r2).Trim()
wsl -d Ubuntu-24.04 -- bash "$wslR2/core/build_linux.sh"
wsl -d Ubuntu-24.04 -- bash "$wslR2/core/run_linux.sh"
Set-Location tools
python score_raw.py --platform linux --no-overlays
python report_tables.py
Set-Location ..
```

Android 交叉编译脚本针对 `android-23` 生成 x86_64 与 arm64-v8a。x86_64 模拟器只支持到 SSE4.2，因此脚本仅对该 ABI 禁用 ncnn AVX/AVX2/AVX512/FMA/F16C；arm64-v8a 保持默认 NEON。先在 Android SDK 中创建并启动 `system-images;android-23;default;x86_64` 的 AVD（本次名称 `wp17r2api23`），等待 `adb shell getprop sys.boot_completed` 输出 `1`。运行器会核对 API/ABI、push 模型和 12 张样例，执行冷启动、10 张批处理及全量识别，然后拉取原始 JSON。模拟器只用于兼容性与识别结果核对。启动模拟器应另开后台进程，再轮询开机状态；下面的两段命令须分别执行。

```powershell
$sdk = 'D:\Dev_SDKs\Android_studio_SDK'
$env:ANDROID_SDK_ROOT = $sdk
& "$sdk\cmdline-tools\latest\bin\sdkmanager.bat" 'system-images;android-23;default;x86_64'
& "$sdk\cmdline-tools\latest\bin\avdmanager.bat" create avd -n wp17r2api23 -k 'system-images;android-23;default;x86_64'  # 仅首次创建
Start-Process -FilePath "$sdk\emulator\emulator.exe" `
  -ArgumentList @('-avd','wp17r2api23','-no-window','-no-audio','-no-snapshot','-no-boot-anim','-gpu','swiftshader_indirect','-no-metrics') `
  -WindowStyle Hidden
```

```powershell
do { Start-Sleep -Seconds 2; $boot = (adb shell getprop sys.boot_completed).Trim() } until ($boot -eq '1')
adb shell getprop ro.build.version.sdk   # 23
adb shell getprop ro.product.cpu.abi    # x86_64
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File core\build_android.ps1
# 若只需重新构建模拟器 ABI：
powershell -NoProfile -ExecutionPolicy Bypass -File core\build_android.ps1 -Abis x86_64
$androidCli = "$assets\build-android-x86_64\wp17r2_ocr"
$strip = 'D:\Dev_SDKs\android-ndk-r27b\toolchains\llvm\prebuilt\windows-x86_64\bin\llvm-strip.exe'
& $strip --strip-all -o "$androidCli.stripped" $androidCli
python tools\run_android.py --cli "$androidCli.stripped" --assets $assets
Set-Location tools
python score_raw.py --platform android --no-overlays
python report_tables.py
Set-Location ..
```

Windows Tesseract 安装包不带本实测所需头文件/导入库，`core/tess_c_api.h` 声明用到的 C API，`core/make_tess_implib.py` 从 DLL 导出表生成 MSVC 导入库。Linux 无 sudo，使用 wheel 自带共享库及 SONAME 链接。该工具链是复现实测的辅助件，不代表最终产品打包方案。

## “识别结果 → 可编辑任务草稿”数据契约

参考实现为 [`evidence/wp17r2/tools/adapter.py`](evidence/wp17r2/tools/adapter.py)，schema `wp17r2-draft/1`。输入是同一 CLI 的原始 `images[].lines[]`（文本、置信度、矩形框）及原图；与标注 JSON 无关。输出每张图的 `id/width/height/engine`、几何排序后的 `rows`、`tasks`、`dropped`、`noise_lines` 和 `notes`。每个 task 含 `row`、`line_indices`、`anchor_line`、可编辑 `title`、布尔 `checked`、`checkbox_box/fill`、`level`、`parent`（指向草稿行）、原样 `due` 文本和 `needs_confirmation[]`。`parent`、`due` 都只是草稿推断，不能直接写入正式任务库；`due` 不等同于已解析的日期或提醒。

草稿处理规则：以 OCR 框的纵向重叠合并行，再按位置排序；以原图左侧 gutter 的复选框判断任务及勾选态，忽略识别成 `V/√` 的框内文字；顶部状态/标题区、右侧元信息和无复选框的分区标题保留在 dropped 供审核。缩进只推断 0/1 两级；找不到父任务或行被拆成多个文字块时记录 `needs_confirmation`。重复图只生成 `hint_only: true` 的跨图提示，绝不自动合并或删除。UI 必须逐项提供编辑、跳过、确认，取消或未确认时不写任务库。原图和中间结果不进入日志或持久任务库。

## 许可证、分发与风险

| 组件 | 本次来源及许可核对 | 分发前动作 |
|---|---|---|
| ncnn `c6b351b...` | [ncnn LICENSE](https://github.com/Tencent/ncnn/blob/master/LICENSE.txt)：BSD-3-Clause，内含第三方条款 | 随产物保留许可与相关第三方声明 |
| PP-OCRv5 原始 mobile 模型/字典 | [PaddleOCR LICENSE](https://github.com/PaddlePaddle/PaddleOCR/blob/main/LICENSE)：Apache-2.0；本次 ncnn 转换权重来自[第三方示例仓库](https://github.com/nihui/ncnn-android-ppocrv5)，`assets.lock.json` 固定字节与哈希 | 第三方仓库未见独立 LICENSE；核对转换权重的再分发权限及来源，或自行从上游模型转换并固定版本 |
| Tesseract 5 / `tessdata_fast` | [Tesseract LICENSE](https://github.com/tesseract-ocr/tesseract/blob/main/LICENSE) 与 [tessdata_fast LICENSE](https://github.com/tesseract-ocr/tessdata_fast/blob/main/LICENSE)：Apache-2.0 | 保留许可及语言包来源、哈希 |
| Leptonica | [Leptonica 许可文件](https://github.com/DanBloomberg/leptonica/blob/master/leptonica-license.txt)：两条再分发条件，BSD-2-Clause 类许可 | 打包 Tesseract 时保留版权和免责声明 |
| stb_image.h | [头文件内许可](https://github.com/nothings/stb/blob/master/stb_image.h)：MIT 或公有领域双选项；本次选 MIT | 分发时保留 MIT 版权和许可文本 |

`assets.lock.json` 只锁定下载文件的哈希和 URL，不锁定各上游许可版本或第三方转换仓库 commit。模型、语言包与编译产物均不提交本仓库。

未解决的产品风险：

1. 语料是统一样式的合成截图，没有真实应用的压缩噪声、渐变、阴影、异形图标和不同字体。指标是此语料上的相对比较，不能当作真实应用绝对准确率。
2. 适配器是几何启发式：顶部 `0.22 × 图片宽度` 视为 chrome、缩进只分两级、勾选靠填充率阈值 0.5、无复选框文字视作分区；删除线、复杂父子关系和真实日期解析未覆盖，需可配置和人工确认。
3. Windows ncnn 4 线程峰值 449 MiB，API 23 真机尤其低内存设备需要做多图限流、峰值与耗时测试。模拟器冒烟不能替代真机验收。
4. Android Tesseract 未构建/未运行；arm64-v8a 仅编译通过。x86_64 模拟器的无 AVX 构建与 arm64 真机 ABI 并非同一性能配置。Linux 是 WSL2，且 Tesseract 版本与 Windows 不同，跨平台耗时不可直接比较。
5. 第三方 ncnn 转换权重的分发授权尚需落实，正式发版前必须核清来源和许可。
