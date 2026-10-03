# WP17-I7：真实 Linux 选择器与独立进程重开

执行日期：2026-10-03（Asia/Shanghai）。基线 **`3ac0b6d9192a0495f1db1f636d9b8726b03179c4`**，分支 `codex/wp17-i7`，工作树 `D:/Dev_project/martix-wp17-i7`，ext4 镜像 `/home/ubuntu/wp17i7-private/repo`。本树没有适用的 AGENTS.md。提交身份通过 `git config --worktree` 设置为 `wp17-i7-agent <wp17-i7-agent@local.invalid>`；最终完整 commit、文件清单在提交后生成的 `D:/Dev_project/martix-wp17-i7-private/handoff.json`，也在交接回复中提供。

**真实 GTK 多选、官方 native OCR、失败保存重试及两个独立应用进程的磁盘重开均已通过。** 验收应用是 Linux debug integration harness，调用生产 `ScreenshotImportPage`、默认 `LocalScreenshotBackend`、`pickScreenshotPngFiles`、预览和 Store；不是完整首页/main 入口的发行包。没有注入 picker 返回文件列表、OCR 文本、draft 或 bitmap。唯一存储故障接缝是已有 `saveWriter`，凭据使用空 CredentialStore，避免访问用户密钥环。

## 修复和文件边界

- `native/ocr/tools/drive_official_import.py`：修复 I6 Linux 驱动。zenity 4 / GTK4 将 `--filename=<fixtures>/` 显示成父目录中选中的 fixtures 文件夹；旧驱动在父目录执行全选，选中了文件夹，确认无法返回 PNG。新驱动在真实 GTK Location 控件中输入**单个目录**并清空旧输入，然后使用真实文件列表的 AT-SPI Selection 接口选择五行，逐项检查被选行名，触发真实确认按钮的 Action。文件结果仍完全由原有 file_picker/zenity 返回。GTK4 在此 Xvfb 环境的控件屏幕坐标为 `(0,0)`，故不使用这些坐标定位；每次操作重新读取可访问性树，容忍导航时消失的子节点。保留取消、选择前/后原始 XWD 和选择行 JSON。
- `native/ocr/tools/wp17_i6_linux.sh`：在自己启动的 Xvfb 内声明显示身份，禁用继承的 Wayland 入口，接入修复后的驱动。原 `--file-entry` 模式仍明确表示注入选择，I7 不使用它。
- `native/ocr/tools/wp17_i7_linux.sh`、`drive_linux_reopen.py`：默认关闭、显式启用的构建/验收；约束 ext4 镜像、固定 SDK、专属产物和 XDG 根；直接启动并 waitpid 实际应用。每次创建新 run 目录，两个阶段复用同一数据根。保存失败及非零/被信号终止的进程不能被旧成功报告覆盖。故障证据和原始数据库保留。
- `test/wp17_i7_device_test.dart`：生产选择入口的取消/多选/native OCR/校对/失败重试和独立磁盘读取；只有编译时 `WP17_I7_DEVICE=true` 才启用。测试在 suite 完成、包括 teardown 结果确认后，自行 `exit(0/1)` 并落地原始结果，host 不终止成功应用。
- `native/ocr/tools/test_ocr_linux_drive.py`：七项驱动回归，覆盖显示隔离、目录导航与真实行选择、选择行不符、可访问性子节点消失、虚假重开/选择报告和实际失败退出码。

没有修改产品选择函数：问题属于驱动及 GTK4 环境交互。没有改识别/解码/资源策略、native ABI、模型锁、Store/SaveProtocol、备份、Windows runner、Android 接线、版本或共享导航/路线图。没有另派 Agent、push、amend、tag、Release 或创建签名凭据。只提交上述源码、测试及本 NOTES；生成注册文件、资源和二进制均未提交。

## 实际流程与重开证据

最终运行 `L/runs/run-vIGXFx`（L = `/home/ubuntu/wp17i7-private`），运行用户 ubuntu / UID 1000；专属 Xvfb `:100`、独立 dbus，XDG 数据根 `L/runs/run-vIGXFx/data`。既有 WSLg 用户桌面未被操作。

沿用原 R2 三张真实合成 PNG（中/英/日），另复制中文图作为重复图，并增加 `not a png` 损坏图，共五个文件；原 R2 黄金 drafts 未修改。每个成功图产生八个候选，两次批次均保留一张损坏图的逐图错误、重复提示和待确认状态。五个输入的运行前/后 SHA256 相同，源文件保留。

1. 关闭真实选择器：任务为空、pointer 不变，所有 Store writer 调用和 pointer 写入次数均为零。
2. 第一批真实多选 → native OCR → 校对取消：任务为空、所有 Store writer 调用和 pointer 写入次数仍为零，未确认不能提交。
3. 第二批真实多选：核对原 R2 title/checked/parent/due；提交按钮保持禁用。通过 UI 明确跳过重复图、确认重复提示及各任务、修改标题、保留一项日期原文，选择新目标板和象限 1。
4. `saveWriter` 只在 `SaveProtocol.pointerKey` 返回 false；槽和 SharedPreferences 平台写入仍真实。原协议发生两次失败 pointer 尝试，旧 pointer/Store 不变；校对字段逐项保持。一次 UI 重试产生第三次 pointer 尝试、**唯一一次成功 pointer**；重试 ID 与失败槽中尝试的 ID 相同。
5. 最终两块板、18 根任务 + 6 子项 = 24 条，6 项完成。根/子 ID 唯一，父子结构、目标板与象限正确；日期原文仅为备注，deadline/plannedDate/reminderAt/completedAt 不自动生成。
6. 第一个应用完成测试与 dispose，正常退出并被 host waitpid。第二个应用随后从**同一磁盘数据根**创建生产 Store/init，读取真实 SharedPreferences；比较板全部字段、activeBoardId、任务全部字段和嵌套子项、ID、完成态、备注、日期、设置和 schedule，以及提交 pointer。expected.json 仅作比较，没有写入 prefs/Store。原始数据库另存 `disk-after-import`。

| 实际应用 | PID | exit | 时间 | VmHWM 峰值 |
|---|---:|---:|---:|---:|
| import | 13321 | 0（正常） | 75075 ms | 1089020 KiB |
| 独立 reopen | 18390 | 0（正常） | 1203 ms | 341064 KiB |

内存是实际 PID 的 `/proc/status` VmHWM，不是 PSS 或低端设备保证。第一轮成功 `run-Paknht` 也有独立 PID 34051/35930、各 exit 0；最终以 `run-vIGXFx` 为准。

关键原始证据：最终 run 中的 `host.json`、`process-import/reopen.json`、`flow-import/reopen.json`、`application-import/reopen.log`、`expected.json`、`picker-2/3.json`、`picker-*-opened/selected.xwd`、`session.log`、`session-exit.txt`。Windows 可直接查看的副本位于 `D:/Dev_project/martix-wp17-i7-private/linux-evidence/runs/run-vIGXFx`。失败与成功使用不同目录，没有删除失败后包装成通过。

## 隔离资源与摘要

Windows 私有工具/证据根 W = `D:/Dev_project/martix-wp17-i7-private`，Linux 私有根 L 如上。模型/deployment/xdotool 初始从 I6 私有缓存只读复制；I6 使用的 ncnn SDK 从其记录的 `/home/ubuntu/wp17i4-ncnn-linux/install` 只读复制至 `L/ncnn-install`。ncnn pin 沿用 `c6b351b56fbe32e0381ae00331e3df649b20d7b7`，静态库 24616118 B / `d6dea6d6eba1a50ab8774de131753c4d8ef7b18bd5bca8f058903461948b0c18`；stb 283010 B / `594c2fe35d49488b4382dbfaec8f98366defca819d916ac95becf3e75f4200b3`。

五个部署权重/字典、许可和完整 conversion provenance 经当前 `stage_official_bundle.py --check` 与 reviewed lock 核验，摘要同 I6 表；没有重新转换或使用历史未授权权重。官方来源及许可证详见 I6 NOTES 和未改动的 models.lock.json。逐文件产物摘要在 `L/logs/artifact-checks.json`；最终 bundle `L/artifacts/linux-device-ksSivD`，native 库 17395752 B / `e9e95e1611f4526589b562480a3f862668fb01dc62384ca4e0fe4e8116754dde`。

Linux Flutter `/home/ubuntu/develop/flutter`、Windows formatter `D:/Dev_SDKs/Flutter_3.32.8` 均为 Flutter 3.32.8 / Dart 3.8.1。所有 pub 缓存与临时数据位于 L/W。复制的 I6 hosted 源码未带 hosted-hashes，首次 offline pub get 曾改写镜像 lock 的 hash；恢复本树原 lock 后，从官方 pub.dev 下载精确锁定包，`flutter pub get --enforce-lockfile` exit 0，最终逐字节 cmp exit 0。没有升级依赖；原 lock SHA256 `93c91e4363a690e04b2e84613e7137bda02ecd18f493910bebbe816249a4b755`。

## 命令、退出码和复用

以下在独立 ext4 镜像执行，依赖和源码同步过程的脚本保留于 W；同步排除 `.git/.dart_tool/build/.gradle/.cxx/local.properties`。

```bash
export WP17_I7_ENABLE=true
export WP17_I7_ROOT=/home/ubuntu/wp17i7-private
export WP17_FLUTTER=/home/ubuntu/develop/flutter
export WP17_NCNN_INSTALL="$WP17_I7_ROOT/ncnn-install"
export WP17_I7_DEPLOY="$WP17_I7_ROOT/official-deploy"
export WP17_OCR_STB_DIR="$WP17_I7_ROOT/assets/third_party"
cd "$WP17_I7_ROOT/repo"
bash native/ocr/tools/wp17_i7_linux.sh build
export WP17_I7_APPLICATION="$(cat "$WP17_I7_ROOT/logs/latest-bundle.txt")/matrixflow_native"
bash native/ocr/tools/wp17_i7_linux.sh accept
```

| 实际检查/命令 | exit | 原始日志 |
|---|---:|---|
| `flutter analyze --no-pub`（最终源） | 0 | L/logs/analyze-delivery.log |
| `flutter test --no-pub`（默认全量） | 0 | L/logs/flutter-full.log：1369 passed / 46 skipped |
| 下述七文件定向回归，真实官方 native 启用 | 0 | L/logs/flutter-targeted.log：78 passed / 0 skipped |
| `flutter test --no-pub test/wp17_i7_device_test.dart`（默认关闭） | 0 | L/logs/flutter-i7-gate.log：1 skipped；不是设备验收 |
| `python3 -m unittest discover -s native/ocr/tools -p 'test_ocr*.py'` | 0 | L/logs/python-delivery.log：28 tests / 5 Windows-only skipped |
| Windows 同一 Python 集合 | 0 | W/python-win-delivery.log：28 tests / 1 POSIX-only skipped |
| `bash -n native/ocr/tools/wp17_i6_linux.sh native/ocr/tools/wp17_i7_linux.sh` | 0 | L/logs/bash-delivery-exit.txt |
| `flutter pub get --enforce-lockfile`、原 lock cmp | 0 / 0 | L/logs/pub-get-enforced.txt、lockfile-compare-exit.txt |
| 上述 I7 build / accept | 0 / 0 | L/logs/build-device.log、run-vIGXFx/session-exit.txt |
| `stage_official_bundle.py --deploy L/official-deploy --out <最终 bundle>/data --check` | 0 | L/logs/bundle-check.log |
| 不启用的 I7 shell 和 Python driver | 0 / 0（SKIPPED） | L/logs/default-device/driver-gate.txt；没有启动设备 |
| `git diff --check` | 0 | 提交前检查 |

定向实际命令：先设置 `WP17_OCR_TEST_LIBRARY=<bundle>/lib/libmatrixflow_ocr.so`、`WP17_OCR_TEST_ASSETS=L/official-deploy`，执行 `flutter test --no-pub test/wp17_i3a_screenshot_capture_test.dart test/wp17_i3b_capture_test.dart test/wp17_i3b_submission_test.dart test/wp17_import_preview_test.dart test/wp17_i3b_page_test.dart test/wp17_i3a_native_capture_test.dart test/wp17_i1_ocr_runtime_test.dart`。包含十二张原 R2 对照和十图 native capture，后者是测试 runner 流程，不是十图 GTK 设备满批。

## 保留失败、清理和未验证项

- 原驱动失败复现：`L/baseline/wp17i6-private/logs/drive-linux.log`、`host-linux.json` 和 `L/logs/baseline-picker.txt`，host exit 1，取消已通过、多选不能关闭。使用只读复制的 I6 app bundle及基线原驱动，独立 XDG/Xvfb。
- `run-6AjHdl`：初版坐标/滚动导航失败，host 1，实际 app 被 SIGTERM / -15；原始 process/host/log 保留。改用 Location + GTK Selection/Action 后 `run-Paknht` 完整通过。
- `run-NwwEug`：最终复跑发现 GTK 导航过程中 child 变为 null；host 1、app -15，失败 JSON 明确保留。增加消失子节点回归与读取容错后，`run-vIGXFx` 完整通过。
- 初次 Windows Python 验证因清空环境后测试调用 Path.home 失败，exit 1，W/python-win.log 保留；改为不依赖 home 的纯显示门禁用例后，最终 28 tests 通过。
- 自有 Xvfb/dbus 会话已退出；两条独立诊断产生的辅助 accessibility dbus，按 PID、exe、DISPLAY 和本包 XDG 根逐项核对后清理。`L/logs/cleanup-before.json` 与最终 `cleanup-audit.json` 显示 **live_owned_processes=[]**。保留五次 run 的私有磁盘、原图和失败/成功证据；保留模型缓存及产物供复核，没有删除用户源文件或其他 Agent 的目录。

未验证：完整生产 main/发行包的首页导航；修复后的旧 I6 harness 全流程另跑；GTK/zenity 的其他版本、kdialog/qarma、其他桌面和 locale；真实个人截图质量、低端设备、十图 GTK 设备满批、长时稳定性；Android/Windows 本轮没有设备验收。没有修改或等待 Q1 优化；本轮运行的是共同基线识别运行时，集成后的组合仍需由集成端验证。
