# WP17-Q1：官方 OCR 资源与质量实测

基线 `3ac0b6d9192a0495f1db1f636d9b8726b03179c4`，分支 `codex/wp17-q1`，独立工作树 `D:/Dev_project/martix-wp17-q1`。提交身份仅本树 `wp17-q1-agent <wp17-q1-agent@local.invalid>`；完整提交 SHA 随交接提供。先读 Q1 指定的 evaluation/I1/I5/I6、运行时、模型锁和 R2 参考；未找到适用的 AGENTS.md。

结论：同机 Release 原生重用会话峰值下降约 61%（Windows）/55%（Linux）；Linux Flutter 五批完整流程峰值下降约 40%。原生耗时增加，不能称为速度优化或低端设备验收。R2 文字/几何无变化。独立合成真值暴露空格丢失和长行草稿漏检，未在资源提交中改质量阈值。

## 提交范围

- `native/ocr/ocr_runtime.cpp`：直接 RAII 持有 stb 的 RGB 分配并原地交换 BGR，去掉第二份全图；关闭 det/rec 的 Net 本地缓存池，使 lightmode 死对象可直接释放。模型、算子、线程参数、阈值和 C ABI 不变。
- `lib/screenshot_import/gutter_scan.dart`、`screenshot_capture.dart`：保留原左四分之一亮度/alpha/扫描算法，将紧凑灰度传给 isolate。选择函数和接口不变。仍完整解码 PNG，仍保留本批原始编码字节到重复提示计算完成，草稿保留到校对取消/提交。
- `native/ocr/tools/q1_{benchmark,profile,dart_profile,pool_experiment,quality,limits,report}.py`、`q1_linux.sh`、`q1_cases.json`：显式运行的基准、私有探针、失败方案复现、独立真值和边界工具。
- `tool/wp17_q1_benchmark.dart`、`test/wp17_q1_gutter_test.dart` 和本 NOTES。

没有改 `lib/ocr/ocr_runtime.dart`、backend/page、适配器、提交事务、Store、runner、工作流、依赖/模型锁或 R2 golden。未派 Agent、推送、amend、打 tag 或创建 Release。模型、字体、图像、二进制和运行输出不提交。

## 环境与证据

以下缩写仅用于本记录：

- `W = C:/Users/20214/AppData/Local/wp17q1-private`。桌面虚拟化对应的真实文件根为 `C:/Users/20214/AppData/Local/Packages/OpenAI.Codex_2p2nqsd0c76g0/LocalCache/Local/wp17q1-private`；WSL 从这个根只读复制合成样本。
- `L = /home/ubuntu/wp17q1-private`，自己的 ext4 baseline/after 镜像、pub-cache、构建、日志、Xvfb/DBus/XDG。baseline 用 `git --git-dir=/mnt/d/Dev_project/martix/.git archive <完整基线>`，不使用 Windows 工作树的 .git 指针。
- Windows Flutter `D:/Dev_SDKs/Flutter_3.32.8`、Linux `/home/ubuntu/develop/flutter`，均 3.32.8 / Dart 3.8.1；锁版本未升级。Linux 离线 pub 缓存缺 hosted-hashes，只在私有镜像校验除 hash 描述外完全一致后恢复基线 lock；源工作树 lock 不变。
- Windows ncnn：`C:/Users/20214/AppData/Local/wp17i5-private/assets/ncnn-build-win/install`；stb 同包 `assets/third_party`；模型 `wp17i5-private/deploy-win`。Linux SDK `/home/ubuntu/wp17i4-ncnn-linux/install`，stb `/home/ubuntu/wp17i5-private/assets/third_party`，模型 `/home/ubuntu/wp17i6-private/official-deploy`。旧目录只读复用。
- Windows VS2022/CMake 4.1.1，Linux Ubuntu-24.04/clang 18.1.3/Ninja。请求线程数 4；Linux SDK 未链接 OpenMP，不能宣称有效四线程并行。WSL/Xvfb 软件渲染不是物理 Linux/手机验收。

摘要（SHA256）：

| 对象 | 摘要 |
|---|---|
| ncnn 源提交 | `c6b351b56fbe32e0381ae00331e3df649b20d7b7`（Git SHA） |
| Windows ncnn.lib | `7a3da36c6295ab64d1c40b1f4ad123daa72daf916d6612a129cc21f9e955312f` |
| Linux libncnn.a | `d6dea6d6eba1a50ab8774de131753c4d8ef7b18bd5bca8f058903461948b0c18` |
| stb_image.h | `594c2fe35d49488b4382dbfaec8f98366defca819d916ac95becf3e75f4200b3` |
| Windows before/after DLL | `7f19c6254fb1515cf60c3d615640dabb5198905b54fbc70e1ebf881616d6fbb0` / `06e17fbe45e18d9676f190c2993143793ae0056d2f74b30040994ea9759fc89c` |
| Linux before/after SO | `e35b54ed487797ace9c45aec1d6e279ca18602cc75deccbbb26ca311dfae02db` / `50598ea3228aebbae49efd7baa79bbe4d8aec6f8548eb817aba30bd506c7f984` |

五文件模型共 10,717,392 字节，每次原生基准核对既有 `models.lock.json` 的五个摘要，保存在 `W/bench-win-{before,after}/summary.json` 和 `L/bench-linux-{before,after}/summary.json`；完整模型条目以既有锁为准。

## 方法与测量

`q1_cases.json` 十图含中/英/日、大小字、深浅背景、缩放和两项重复，共 742,720 字节、14,738,760 像素，符合未改动的 48 MiB/24 Mi 像素总上限。原 R2 十图批次也合法（20,003,760 像素），另由实际模型 capture 回归覆盖；未删掉识别内容凑预算。

原生：三个独立进程分别单图、一个会话重用五批各十图、每图销毁重建五批各十图。冷表示新进程，文件系统缓存不受控；热中位数排除第一批。父进程每 20ms 采样实际 PID 的 RSS/HWM/PSS；短峰可能被 RSS/PSS 采样漏掉，HWM 是进程高水位。Windows HWM 是 PeakWorkingSet，Linux 是 VmHWM；以下只在同平台、同构建、同输入的同一指标之间比较，PSS 不当 RSS。

所有值 KiB；`RSS峰 / HWM / PSS峰`，Windows PSS 不可用。

| 平台/模式 | before PID；峰值 | after PID；峰值 | 热十图中位耗时 before → after（ms） |
|---|---|---|---|
| Win 单图 | 29772；365216 / 365312 / — | 50544；150588 / 175924 / — | 冷单图，见原始记录 |
| Win 重用 | 43980；466380 / 467288 / — | 51364；179396 / 182696 / — | 3822.4 → 5839.7 |
| Win 每图重建 | 18448；372216 / 377408 / — | 17208；181600 / 185340 / — | 4798.2 → 7141.9 |
| Linux 单图 | 1968；365440 / 365440 / 356674 | 23271；211032 / 211032 / 201247 | 冷单图，见原始记录 |
| Linux 重用 | 2505；471520 / 472160 / 463190 | 23344；211744 / 211944 / 202551 | 8157.7 → 9916.4 |
| Linux 每图重建 | 10405；378512 / 378512 / 369473 | 25189；213556 / 213940 / 204765 | 7106.1 → 8270.6 |

Windows 重用批后 RSS before 439156→439400，after 五批 52988/52540/52656/52812/53212；after 最终销毁 28100。每图重建后约 28–30 MiB。五批未出现持续线性增长，但不是长时间泄漏证明。主机有并发负载，CPU/文件缓存未隔离；这次重用耗时 Win 增约 53%、Linux 增约 22%，明确是内存/时间权衡。

Flutter：同一显式文件 seam、真实 PNG 解码/原生库、真实 DraftPreview，五批每批 80 个任务、14 个重复提示；完整保留草稿到校对。奇数批由 harness 逐任务确认/确认重复，调用生产 ScreenshotSubmission.commit + Store.flush；偶数批取消并断言 Store 未写入。全部仅在新鲜且检查为空的 XDG 下运行，完成后解除界面/批次引用。选图和确认动作由 harness 驱动，不算真实 picker 或用户点击验收。

| Linux Flutter Release | PID | RSS峰 / VmHWM / PSS峰 KiB | 每批 capture ms |
|---|---|---|---|
| before | 3015 | 1235076 / 1235076 / 1173669 | 8472 / 9043 / 12665 / 13397 / 8923 |
| after | 3335 | 741856 / 741856 / 707343 | 9573 / 9404 / 11148 / 11437 / 7266 |

after idle RSS 207408，五次工作流释放后的 RSS 为 573276/484068/634580/539272/484476；before 为 949828/988344/1115520/1100204/964932。原始逐阶段记录是 `L/flutter-{before,after}.json`；Windows 可读摘要 `W/linux-final-report.json`。首次 before 峰 1108048（`L/flutter-before-initial.json`），同机复跑峰有波动，不能承诺固定上限。没有用 I6 Debug 数值与这里的 Release 计算优化率。

## 根因与未采用方案

私有副本插入数值探针，不记录截图文字；生产无探针。探针耗时不作正式性能数据。

- Linux 首图 native 模型加载后进程 RSS 约 50 MiB，不是纯模型占用。before det 提取 342324、rec 返回 365712 KiB；after det 提取 119192（阶段 VmHWM 210712）、rec 返回 66276。Net 缓存池保留已死 blobs/workspace/可复用的大缓冲是主要成本；不是“10.7 MB 文件应等于10.7 MB RSS”。allocator 复用大块不要求精确尺寸。
- stb 的全图 RGB→BGR 第二份在 12 Mi 像素上限多用 36 MiB，现原地转换且 RAII 释放。
- Dart 首图 rawRGBA 6,060,960 字节；before 传输也为 6,060,960，after 为 378,810（1/16）。像素上限处从 48 MiB 传输变为 3 MiB，完整 RGBA 解码仍存在。首图 raw/transfer/scan RSS before 247068/253084/254620，after 248396/249164/249804 KiB。isolate/library/session/native-return/session-destroy 依次 before 255132/255388/286164/603792/323256，after 250060/250316/280584/365044/310040。整进程快照包含引擎、分配器、线程和解码驻留，不能拆成纯 payload 加和。探针日志 `L/logs/dart-profile-run-{before,after}.log`，native `profile-run-*`。
- 未采用显式 scratch pool（ratio .75、drop threshold 2、每图 clear）：Win 重用峰 295000，比选定方案 182696 高约 61%；热十图约 4294ms，虽快但回到更高峰且增加生命周期代码。`q1_pool_experiment.py`、`W/bench-win-pool`、`W/pool-src`保留失败方案。
- `MALLOC_ARENA_MAX=2` 仅诊断 ablation，before Flutter PID2786 峰 940068/PSS905004，说明 glibc arena 驻留影响整进程峰。未作为产品设置；不能推广到 Windows/Android。

## 边界、取消、质量

实际官方 DLL/SO 的原 R2 validator：12 图、274 行、文字差异 0、最大几何差 0；重用三轮、销毁重建两轮；缺文件、坏/空/超字节 PNG、超宽/高/像素和缺模型八种拒绝路径均通过。

`q1_limits.py` Win/Linux 真 PNG：宽4096、高8192、12 Mi 像素、恰16 MiB文件被 native 接受；16 MiB+1拒绝，拒绝后原会话恢复，再销毁重建重复一次。另实际 Flutter 十图：

- 像素批恰 25,165,824 像素、88,725 字节；10 图全部解码/原生 OCR/适配成功，空白真值草稿为0任务，2236ms。
- 字节批 50,319,948 字节（距48 MiB仅11,700字节）、16,764,416像素；未压缩 IDAT 加合法 ancillary padding，10 图全部成功、0任务，1881ms。
- 这两批是边界压力、不是文字质量样本。PID16445，末尾再运行真实首图 OCR 取消，整进程峰 RSS872188 / VmHWM883580 / PSS839589；像素/字节批结束时累计 HWM分别632828/795740。没有 before 边界对照，不算优化率。`L/flutter-limits-after.json`，退出0。

取消定时器在实际 recognizer 进入时启动：允许当前 native 调用完成，抑制后续图片/草稿；dispose 后重开、坏 PNG 后恢复均实测。回归另覆盖暂存源 finally 清理、异常释放、总字节/像素预算和重复批次。进程退出后自己的 XDG 清理，未触碰正常应用数据。

独立八幅合成图，30 条任务真值：14/18/24/28/32/36/42px，中英日混排、日期/数字、长行、密集父子任务、勾选、深浅背景。自编文字/几何先于 OCR；只用本地 OS 字体，不分发字体，不扫描用户图像目录或上传。`q1_quality.py`、`W/fixtures/labels.json` 包含生成器/字体/PNG SHA 和授权；最后重生成核对全部 PNG/真值完全相同。Win/Linux after 与 before **完整 native JSON 相同**。

- 按 R2 去空白口径 CER 0/449，漏文字行0；保留空格的严格 CER **55/504=10.91%**（55个空格丢失），不能说文本完美。原始额外识别22行/14字另报，未藏入任务文字 CER。
- 草稿28/30，匹配的28项勾选28/28、父子28/28，无额外任务；两条长行文字被识别但没有草稿。1600宽图的29px复选框小于原 `.022*width` 阈值35.2，这是既有任务结构漏检，资源提交不改阈值/真值。
- 校对可改已有任务的文字、空格、勾选、父子/日期；零候选的长行不能靠自动校对恢复，需要独立质量补丁与协调适配器范围。真实授权去标识截图未提供，真实质量未验；14px合成成功不代表真实小字质量。

## 实际命令、退出码与复现

Windows 命令在本工作树执行。下列 `W/L` 按前文展开；日志的 `.exit` 有记录，未记录 `.exit` 的命令取本次工具执行退出码。

| 命令/运行 | 退出与结果 | 证据 |
|---|---|---|
| `D:/Dev_SDKs/Flutter_3.32.8/bin/flutter.bat analyze --no-pub` | 0，无问题 | W/logs/analyze-final.{log,exit} |
| 同 SDK `flutter.bat test --no-pub` | 0，1407通过、10跳过 | W/logs/flutter-full.{log,exit} |
| 实际模型环境的 `flutter.bat test --no-pub test/wp17_q1_gutter_test.dart test/wp17_i1_ocr_runtime_test.dart test/wp17_i3a_native_capture_test.dart test/wp17_i3a_screenshot_capture_test.dart test/wp17_i3b_capture_test.dart test/wp17_i3b_page_test.dart test/wp17_i3b_submission_test.dart` | 0，65通过；设置 WP17_OCR_LIBRARY=after DLL、WP17_OCR_ASSETS=只读deploy-win | W/logs/targeted-initial.log |
| `python -m unittest discover -s native/ocr/tools -p 'test_ocr*.py'` | 0，21通过 | W/logs/python-tests.log |
| `dart.bat format --output=none --set-exit-if-changed lib/screenshot_import/gutter_scan.dart lib/screenshot_import/screenshot_capture.dart test/wp17_q1_gutter_test.dart tool/wp17_q1_benchmark.dart`，`python -c "import pathlib,py_compile; [py_compile.compile(str(p),doraise=True) for p in pathlib.Path('native/ocr/tools').glob('q1_*.py')]"`、`bash -n native/ocr/tools/q1_linux.sh`、`git diff --check` | 均0 | 格式/语法/差异检查 |
| Windows before/after `cmake -S <baseline-src或native/ocr> -B W/native-win-<mode> -G 'Visual Studio 17 2022' -A x64 -Dncnn_DIR=<SDK>/lib/cmake/ncnn -DWP17_STB_DIR=<stb>`；`cmake --build <build> --config Release --parallel 4` | configure/build各0 | W/logs/win-{before,after}-{configure,build}.log；CMakeCache.txt |
| Linux before/after `cmake -S <repo>/native/ocr -B L/native-linux-<mode> -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_COMPILER=clang++ -Dncnn_DIR=/home/ubuntu/wp17i4-ncnn-linux/install/lib/cmake/ncnn -DWP17_STB_DIR=/home/ubuntu/wp17i5-private/assets/third_party`；`cmake --build <build> --parallel 4` | 各0 | L/logs 与对应 CMakeCache.txt |
| Win/Linux `python native/ocr/tools/q1_benchmark.py --library <before或after库> --assets <官方deploy> --build Release --out <W或L>/bench-<平台>-<mode>` | 每个平台两个完整父进程均0，子模式均0 | bench-*/summary.json、模式JSON/samples/stderr |
| `python native/ocr/tools/validate_official_runtime.py --library <after库> --assets <deploy> --report <W或L>/validate-<平台>-after.json` | Win/Linux各0，原 R2不变 | validate-*-after.json |
| `wsl -d Ubuntu-24.04 -- bash /mnt/d/Dev_project/martix-wp17-q1/native/ocr/tools/q1_linux.sh setup`，随后 `build-before/build-after/run-before/run-after/profile/dart-profile/quality/limits` | 最终各0，Release真实库/应用 | L/logs/*.{log,exit}、flutter-*.json |
| `python native/ocr/tools/q1_quality.py generate --out W/fixtures --fonts C:/Windows/Fonts`；`score --out W/fixtures --library <after DLL> --baseline-library <before DLL> --assets <deploy-win> --flutter-report W/flutter-after.json` | 最终各0；Linux `q1_linux.sh quality` 0 | W/logs/quality-*，W和L/fixtures/{labels,native-raw,quality}.json |
| `python native/ocr/tools/q1_limits.py --library <after库> --assets <deploy> --out <W或L>/limits-<平台>` | Win/Linux各0 | limits-*/report.json，L/logs/limits-native-linux.* |
| `python native/ocr/tools/q1_report.py --root <W或L>` | 0 | W/report.json、W/linux-final-report.json、L/final-summary.json |

默认测试不下载模型、不生成基准/图片。所有 opt-in 工具输出外部；ncnn stderr 很多，必须重定向日志。Linux 运行脚本用新 XDG、timeout、Xvfb/DBus；源树镜像不用于提交。原生探针和 pool 生成器有独立 external output，禁止对主树注入探针。

## 修复前失败与未验

- gutter 新测试初始错误期望 x20/50，退出1；核对原 R2 fixture 为 x12/40 后改测试，未改 golden，最终回归0（W/logs/gutter-initial.log）。
- 初始 mixed-light 日文字体缺简体字，人工图片检查发现；改用本地 msyh、添加缺字断言再生成，旧图留 W/fixtures-initial。Windows 读 Flutter JSON 初用默认GBK失败1，改显式UTF-8后0；探针解析误依赖字段顺序失败1，改独立解析后0。
- Linux bootstrap 使用 Windows工作树 .git 指针失败1，改显式对象库 archive 后0。离线 pub hash描述差异经过版本/其余内容校验和恢复，不是依赖更新。
- 首次边界 Flutter 退出1（PID16773）：8×8白图 native 返回空文字框 `[-.25,-1.25,10.5,10.5]`，既有适配器拒绝越界框。旧报告 `L/flutter-limits-after.initial.json`/`L/logs/limits-flutter.initial.*` 和 W/tiny-raw.json 保留（Win before/after输出也相同）；改用32×16合法0行白图，记录逐图错误后最终0。原来的8×8 exact-byte native接受测试仍保留，不隐藏适配器边界缺陷。初版 native 边界断言误要求所有白图0行也失败1，改为仅拒绝输入必须0行（W/logs/limits-win.log）。
- 最后更新生成器 provenance 时误指不存在的 Flutter报告路径，退出1（W/logs/quality-provenance-final.log）；复制实际 L/flutter-after.json 后重跑0（quality-provenance-fixed.log），所有样本哈希/真值不变。
- Android/arm64、专用低端设备、真实 picker/点击确认、真实截图质量、物理桌面渲染、长时间稳定性、严格隔离的速度实验未验。默认10项跳过不算设备验收。最大预算下 Flutter 仍可接近 0.84 GiB HWM，不能宣称低配置支持或 WP17正式支持。
