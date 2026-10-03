# WP17-I6：官方模型 Android/Linux 应用接线与完整导入验收

执行日期：2026-10-03（Asia/Shanghai）。共同基线 `5fb4592ccc10cdcc1698e27f68d2367a3d83cf18`，独立分支 `codex/wp17-i6`，执行树 `C:/Users/20214/.codex/worktrees/wp17-i6/martix`，本地 author/committer `wp17-i6-agent <wp17-i6-agent@local.invalid>`。没有修改主检出、Store/SaveProtocol、备份契约、Windows runner、发行工作流、依赖或公共路线图；不 push/tag/release。

## 实现

- Android 可选 `wp17OcrModels` 指向外部资源目录。构建阶段核对官方模型、字典、上游许可附件和完整资源清单的 SHA256/大小；模型必须同时启用 native OCR。`wp17OcrValidation=true` 仅为 debug 添加 `.wp17i6` 身份，拒绝带该验证开关的 release task。默认配置不包含模型或 native OCR。
- 新 APK-local `com.matrixflow/ocr_assets` 通道在 IO worker 上将已打包的资源验证后整体安装到自身 `filesDir/wp17-ocr`；失败不返回可用目录。不使用下载或外部存储。既有 SAF 通道继续负责实际 content URI 有界读取与临时 PNG 清理。
- Flutter 的资源优先级为环境变量、dart-define、可选 APK/Linux bundle、旧 application-support 路径。Linux 从实际可执行文件旁的 `data/wp17-ocr` 读取，不安装到 `/usr/local/lib`。识别算法和 native ABI 未改变。
- `stage_official_bundle.py` 在发布前检查当前 reviewed lock 与官方 deployment 的 Paddle/ONNX/conversion provenance、权重、字典、许可，生成 12 文件加 manifest 的完整目录；整目录替换，`--check` 只读。五项新增 Python 回归覆盖损坏模型/许可证、过时 provenance、失败时保留旧目录和只读时间戳。
- 专用构建脚本和设备测试均须显式启用。生产主入口也有独立 APK/Linux release bundle；设备 harness 用生产截图页面、校对组件和 Store。凭据使用空端口，保存失败仅通过既有 saveWriter 注入。没有注入识别文本、draft 或 bitmap。

## 工具与隔离

Windows Flutter `D:/Dev_SDKs/Flutter_3.32.8`，Linux Flutter `/home/ubuntu/develop/flutter`：3.32.8 / Dart 3.8.1，framework `edada7c56e`，engine `ef0cd00091`。Android SDK `D:/Dev_SDKs/Android_studio_SDK`，NDK `28.0.12433566`，CMake `3.22.1`，emulator `35.2.10`。专用 AVD `wp17i6api23` / `emulator-5580`，API 23 x86_64，3072 MiB，swiftshader_indirect；没有使用日常真机或正常安装应用。

Linux：Ubuntu-24.04 / WSL2 `6.6.87.2-microsoft-standard-WSL2 x86_64`，CMake 3.28.3、clang 18.1.3、GTK 3.24.41、zenity 4.0.1、Xvfb 与独立 dbus session。xdotool/libxdo 从包解到本包私有 tools 路径，不改系统安装。每次验收生成新的 XDG_DATA/CONFIG/CACHE 目录。

私有根（简称 W/L）：

- W：`C:/Users/20214/AppData/Local/wp17i6-private`。Store 沙箱下物理目录为 `C:/Users/20214/AppData/Local/Packages/OpenAI.Codex_2p2nqsd0c76g0/LocalCache/Local/wp17i6-private`，WSL 应使用物理路径或执行树中转，不能假定逻辑 AppData 路径在 `/mnt/c` 存在。
- L：`/home/ubuntu/wp17i6-private`；`L/repo` 是本执行树的 ext4 源码镜像，没有独立 Git 提交。同步排除 `.git/.dart_tool/build/.gradle/.cxx/local.properties`，避免复制进行中的 Android 锁文件。
- 模型只读复用 I5 私有缓存，验证后复制到各自 `assets`，用当前 publisher 在本包 `official-deploy` 重建 deployment。没有重新转换、下载替代权重或改模型摘要。
- Android SDK 静态 ncnn 库来自已核验私有 SDK：x86_64 `8507abea0095f6c61c6efd912fb24369bb1651ab31a2d4dce432c86a2c71c11a`（89,323,486 B），arm64-v8a `ff736cecd9851452724f3cb1fc47c40d789f83a805ba5855cdcc91eb80c77870`（75,825,212 B）。实际目录为 `ncnn-android-<abi>/install/lib/libncnn.a`。Linux SDK只读复用 `/home/ubuntu/wp17i4-ncnn-linux/install`。ncnn pin `c6b351b56fbe32e0381ae00331e3df649b20d7b7`；stb_image.h `594c2fe35d49488b4382dbfaec8f98366defca819d916ac95becf3e75f4200b3`。
- pub get 未升级依赖。Linux 初次离线缺包退出 69；将当前 lock 所需 hosted package 源码复制到本包 pub-cache 后，offline pub get 退出 0。模型、工具缓存、日志、生成文件和二进制均不提交。

## 官方部署文件

沿用 I5 锁定的 6 个 Paddle 输入、2 个 ONNX 输出、4 个 ncnn 输出及其完整 conversion 环境（22 项版本、pnnx SHA、两次 replay）；`native/ocr/tools/models.lock.json` 未变。模型源标记 `official`，不把历史 nihui 来源描述成可发布来源。

| 文件（相对 wp17-ocr） | 字节 | SHA256 |
|---|---:|---|
| ncnn/PP_OCRv5_mobile_det.ncnn.param | 24256 | `19359eea27e9f38b493a40ac11acbb95bbe6cbe174866e9e043cbe6a786f3ce6` |
| ncnn/PP_OCRv5_mobile_det.ncnn.bin | 2357216 | `857a96bc963725105b78a178dfcc3c0c3db1a7b9eef32244367b2cb105ccf60b` |
| ncnn/PP_OCRv5_mobile_rec.ncnn.param | 19632 | `dbd3a743febb5d08157059d4ae31f9372b413b9739ef9d5963da68c987a2481c` |
| ncnn/PP_OCRv5_mobile_rec.ncnn.bin | 8242276 | `49d9907a55ba20fa6637f9f788f66ab00793bc8ce57a733a09dbe86b9a2e3db0` |
| ncnn/ppocrv5_dict.txt | 74012 | `d1979e9f794c464c0d2e0b70a7fe14dd978e9dc644c0e71f14158cdf8342af1b` |
| licenses/APACHE-2.0.txt | 11376 | `3840c5c0c61c294264d2dd77b8777be6ddd90121ef4e0e64abcd22edea581d6e` |
| licenses/PP-OCRv5_mobile_det.MODEL_CARD.md | 16243 | `4cc20ad6d41af86b3ce9885ffb0956e152574a2eb14179aeb07fd2d3956161ca` |
| licenses/PP-OCRv5_mobile_rec.MODEL_CARD.md | 16075 | `b02727443cef4904a9ee12accdfaf66fcbada7b93a1a05c40dde7582291ba28c` |
| licenses/ncnn-BSD-3-Clause.txt | 6427 | `7c974bac98848df46be1af5bdaa3c3c9c01f6082a90f55caeb7f60c6208aa255` |
| licenses/stb-LICENSE.txt | 2510 | `bebfe904b14301657e4e5d655c811d51fd31b97c455b9cc2d8600d6bac6cff63` |
| licenses/THIRD_PARTY_OCR_NOTICES.md | 6343 | `f54ad9b0c5a4367900c2849e69b374426d3f52f39be7744a36935ee00d17bfe9` |
| deployed.json | 7363 | `9e96032d77aa7f92e598bd20f9482614657356c56d792a6d62aa9e93a65177f8` |

权重加字典 10,717,392 B。APK zip 内两个 ABI 的 native 库和上述 12 文件/manifest 均实际检查；Linux official/device 同样检查，默认产物检查 absence。完整每文件大小/摘要在 `W/logs/artifact-checks.json`、`L/logs/artifact-checks.json`，manifest 在各自 `packaged-assets/wp17-ocr/bundle-manifest.json`。

## 设备流程与证据边界

使用原 R2 三张合成图 `zh_light_base.png/en_light_base.png/ja_light_base.png`，增加中文图的字节副本及 `b'not a png'` 损坏图，共 5 个真实文件。每个成功图 8 个候选，共 32 候选；新 reference_drafts 仅提取原 R2 drafts 的 title/checked/parent/due，三份原文件 SHA 写在 fixture 注释中。真实 OCR 与完整原 drafts 比较，没有重记黄金结果或改成理想识别文本。

共同验收：选择取消零写入；第一批识别后取消零写入；第二批重复警告/损坏图、未确认禁提交；明确跳过重复图，点击每项确认和重复提示，改一处标题、保留一处日期原文、选象限；实际 pointer 写失败保留校对与 Store 原态，重试后恰好一次成功 pointer。既有失败回滚会再尝试 pointer，所以日志是两次失败、第三次成功。最终 24 项＝18 根任务＋6 子任务，6 项完成，日期未自动写 deadline/plannedDate/reminder/completedAt，所保留原文仅进入 notes。实际 prefs.reload 后新 Store.init 与保存前全部任务 JSON 相等，任务计数/根 ID 无重复，临时 PNG 目录为空。磁盘重读在同进程新 Store 完成，未宣称独立进程冷启动。

| 平台 | 最终实际入口 | host exit / 耗时 | 进程峰值 VmHWM | 两个连续批次耗时 |
|---|---|---|---:|---|
| Android API23 x86_64 | 真实 ACTION_OPEN_DOCUMENT / content URI / 生产 SAF | 0 / 112169 ms | 609840 KiB | 29457 / 23541 ms |
| Linux x64 / Xvfb | 显式 real-file entry；驱动选择 5 个真实 PNG，生产 ScreenshotCapture 有界读/解码/native OCR | 0 / 68975 ms | 1210724 KiB | 8289 / 5091 ms |

host 包含 Flutter 启动/驱动协调，batch 包含选择至校对；数字不是纯模型耗时。峰值从应用实际 PID `/proc/<pid>/status` 的 VmHWM 读出，Android 使用 ps 精确包名行避免把 shell PID 当应用。此值不是 PSS、全系统峰值或低端设备保证。Android 已连续两次完整通过，表列最终源码的第二次；Linux file-entry 完整通过一次，含两个连续识别批次。

Android OCR/picker 未注入。Linux 的 `--file-entry` 明确注入文件选择与取消选择，仍读取真实磁盘 PNG，未注入 OCR/draft。报告 `real_picker=false`。真实 zenity/GTK 取消已出现 `cancelled=true`；完整多选驱动未通过（确认后 dialog 未关闭，host exit 1），不计入 Linux GTK 完整通过。保留 `L/logs/drive-linux.log`；通过证据是独立的 `drive-linux-file-entry.log`、`flow-linux-file-entry.json`、`host-linux-file-entry.json`。Android 是 `W/logs/drive-android.log`、`flow-android.json`、`host-android.json`。

## 可复用命令与退出码

在本包独立执行树运行；W/L 仅是上述根的缩写，实际命令需展开路径。构建脚本恢复原 `android/local.properties` 的字节，验证入口默认测试跳过，正常测试不会下载模型。

```powershell
python native/ocr/tools/publish_models.py --assets C:/Users/20214/AppData/Local/wp17i6-private/assets --deploy C:/Users/20214/AppData/Local/wp17i6-private/official-deploy
python native/ocr/tools/stage_official_bundle.py --deploy C:/Users/20214/AppData/Local/wp17i6-private/official-deploy --out C:/Users/20214/AppData/Local/wp17i6-private/packaged-assets --check
.\tool\wp17_i6_android_build.ps1 -PrivateRoot C:/Users/20214/AppData/Local/wp17i6-private -OfficialDeploy C:/Users/20214/AppData/Local/wp17i6-private/official-deploy -NcnnRoot C:/Users/20214/AppData/Local/wp17i6-private/assets -DeviceTest
python native/ocr/tools/drive_official_import.py --platform android --repo . --root C:/Users/20214/AppData/Local/wp17i6-private --flutter D:/Dev_SDKs/Flutter_3.32.8/bin/flutter.bat --application C:/Users/20214/AppData/Local/wp17i6-private/artifacts/wp17-i6-device.apk --serial emulator-5580 --sdk D:/Dev_SDKs/Android_studio_SDK
# 去掉 -DeviceTest 构建生产 main 入口的隔离 APK；加 -Normal 构建正常包，只构建不安装。
```

```bash
export WP17_I6_ROOT=/home/ubuntu/wp17i6-private
export WP17_REPO="$WP17_I6_ROOT/repo"
export WP17_FLUTTER=/home/ubuntu/develop/flutter
export PUB_CACHE="$WP17_I6_ROOT/pub-cache"
export PATH="$WP17_I6_ROOT/tools/usr/bin:$WP17_FLUTTER/bin:$PATH"
export LD_LIBRARY_PATH="$WP17_I6_ROOT/tools/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}"
export WP17_NCNN_INSTALL=/home/ubuntu/wp17i4-ncnn-linux/install
export WP17_I6_DEPLOY="$WP17_I6_ROOT/official-deploy"
export WP17_OCR_STB_DIR="$WP17_I6_ROOT/assets/third_party"
cd "$WP17_REPO"
bash native/ocr/tools/wp17_i6_linux.sh normal
bash native/ocr/tools/wp17_i6_linux.sh official
bash native/ocr/tools/wp17_i6_linux.sh device
bash native/ocr/tools/wp17_i6_linux.sh accept-file-entry
# accept 是保留的真实 GTK 驱动模式，当前完整多选失败，不应改称通过。
python3 native/ocr/tools/stage_official_bundle.py --deploy "$WP17_I6_DEPLOY" --out "$WP17_I6_ROOT/artifacts/linux-official/data" --check
```

| 实际检查 | exit | 结果/日志 |
|---|---:|---|
| flutter analyze --no-pub | 0 | No issues；W/logs/analyze-final.log |
| flutter test --no-pub | 0 | 1399 passed、8 skipped；W/logs/flutter-full.log、flutter-full-exit.txt |
| 定向 Flutter 7 文件（assets/I4/I3B/page/submission/capture/native/runtime） | 0 | 48 passed；W/logs/flutter-targeted.log；此运行显式使用私有 I5 Windows DLL 与本包官方部署，未启动 Windows 应用 |
| Python unittest discover -s native/ocr/tools -p 'test_ocr*.py'（Windows） | 0 | 21 passed；W/logs/python-final-win.log |
| 同一 Python 集合（Linux） | 0 | 16 passed、5 Windows-only skipped；L/logs/python-final.log |
| Android 正常 debug / 官方隔离 main / 官方隔离 device build | 0 / 0 / 0 | W/logs/build-normal.log、build-isolated.log、build-device.log；正常包不安装 |
| Linux 正常 release / 官方 release / 官方 device debug build | 0 / 0 / 0 | L/logs/build-normal.log、build-official.log、build-device.log |
| 官方 bundle --check、实际 APK/Linux 文件 hash/manifest/默认 absence | 0 | 各根 artifact-checks.json；没有改 pin |
| bash -n native/ocr/tools/wp17_i6_linux.sh；git diff --check | 0 / 0 | 脚本语法和差异检查 |
| Android drive / Linux accept-file-entry | 0 / 0 | 上述 flow 与 host JSON |
| Linux 真实 GTK 完整多选 drive | 1 | 没有关闭确认 dialog；未完成完整验收 |

## 可运行产物

APK 均在 `W/artifacts`，official main/device 身份均 `com.matrixflow.app.wp17i6`，normal 身份 `com.matrixflow.app`，包身份另有 `W/logs/apk-*-facts.txt`。debug 签名用于隔离验收，未作为发行包。

| APK | 字节 | SHA256 |
|---|---:|---|
| wp17-i6-normal.apk | 208808789 | `2f6f91bd03fc0f8ae819bacd145bd503e5f6c65388f3ec2956b2ae4135c0c9bf` |
| wp17-i6-isolated.apk（main） | 174914988 | `9a245b25a9d8c25f15ef0ae69a0b3dfae0f95c58bb2083ed63f631c47d49194c` |
| wp17-i6-device.apk | 174210940 | `3878112a86bd25d69c558a4aa7a7854e8e7dec8c65f0c91909ca457729d6fca8` |

Linux 运行须保留整个 bundle，目录 `L/artifacts/linux-normal`、`linux-official`（生产 main）、`linux-device`。不能只拷贝 launcher；完整 Dart AOT/Flutter/native/资源逐文件摘要见 `L/logs/artifact-checks.json`。normal/official launcher 23928 B，SHA `21ac6e7cae8f67b12502cc3348f239dbdc2da2cf5e4a0a457cc0ffd543ea11ba`；official native 16940360 B，SHA `e35b54ed487797ace9c45aec1d6e279ca18602cc75deccbbb26ca311dfae02db`。device launcher 51528 B，SHA `a1c24b8971af17d9cd69172e00d83848b97ad6413388dc73a2e8498587d18d9c`；device native 17395800 B，SHA `3bb8c907c5bbc7ca3c7e4c467961e2c94d5669c142053b56bf1a8e174fbe75ed`。

## 失败、清理与未验收项

真实失败与修正：I5 旧 deploy 的 provenance 仍是旧字段/8 项版本，stager 正确拒绝；从已锁定且摘要匹配的 I5 文件用当前 publisher 重建本包 deploy，未放宽校验。Linux 离线依赖缺失退出 69 后补齐当前 lock 缓存。rsync 曾因活动 Android 锁文件退出 23，改为排除生成目录。模拟器最初 partition-size=2048 超出工具最大 2047，改为 2047。Android DocumentsUI 初次未启用内部存储导致导航失败，修正专用 AVD 的导航；初版测试误用理想英文 OCR 文本、误认为失败只尝试一次 pointer，随后改为原 R2 完整结果及既有协议行为。Linux GTK 驱动失败后选择任务允许的显式真实文件入口，并保留失败边界。

Android host 每次退出 force-stop/uninstall 专用包、删除 `Download/WP17-I6` 与本包 UI dump，并恢复自己改的三个全局动画设置。最后再次确认专用包/目录不存在、设置为原来的 null，关闭专用 AVD。没有安装正常包。API23 的 adb shell 不可靠传递 shell exit code，最终目录检查使用明确 ABSENT 输出；不能把 `adb shell test` 返回 0 当作文件存在。Linux 最终成功运行的 XDG session 由 EXIT trap 删除；先前四个失败运行的专用残留按 canonical private-root 边界清理，剩余 session 为零，已无本包应用进程。清理证据是各根 `logs/cleanup-final.json`。只清理本包可验证的进程，保留私有产物/日志。执行树内生成的 Windows/Linux plugin 文件不提交。

未验收：Android arm64-v8a 仅编译/入包，没有专用真机运行；Linux GTK 真实多选完整流程；真实个人截图识别质量、低端机、10 图设备满批、长时稳定性及独立进程冷重启。现有 capture 回归覆盖 10 张上限和有界读取，实际设备每批 5 张。合成中英日成功不构成 WP17 正式平台支持或发行批准。
