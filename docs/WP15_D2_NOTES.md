# WP15-D2：日程设备验收与实测修复

基线 `39cf8ed6df7f5290a9b45c970f9c5e279c89230a`；分支 `codex/wp15-d2`；工作树 `D:/Dev_project/martix-wp15-d2`。设备执行记录中的 revision 是该基线，dirty=true，表示执行了本包未提交源码；最终完整提交 SHA 随交接给出。固定 Flutter 3.32.8 / Dart 3.8.1，依赖版本沿用原锁文件。本包不代表 WP15 所有设备门禁已完成。

## 改动与实测缺陷

- `lib/platform/device_time_zone_picker.dart`：Linux 原生页面在 320px、3 倍字号下，时区选择器的说明/搜索区域与嵌套结果列表产生 RenderFlex 溢出（实测 1168px）。改为 AlertDialog 的统一滚动区，说明、搜索和结果均可滚动到达。正常设备时区和未知时区两种文案均有回归。
- `test/wp15_d2_zone_picker_test.dart`：上述两种状态的窄屏/大字号回归。
- `lib/widgets/task_card.dart`、`test/wp15_d2_navigation_layout_test.dart`：Android 320px 首页中同时有计划日、截止和提醒的父任务，信息行实测横向溢出 61px，影响进入详情的完整验收。改为可换行布局；新回归在修复前退出 1、修复后通过，保留三个信息并验证父任务安排入口。
- `test/wp15_d2_device_test.dart`、`test/wp15_d2_device_driver.dart`：四个真实 Android/Linux 页面场景和宿主结果回调。默认全量显式 skip，只有 `WP15_D2_DEVICE=true` 才初始化设备 binding。
- `tool/wp15_d2_android.ps1`：显式指定设备、验证 SDK 和 APK 身份、运行中变更系统时区、记录实际进程退出码，finally 恢复时区/自动设置并清理专用包的合成资料。工作树锁防止两次验收并发修改设备。构建和驱动均跟踪自建子进程并限制超时。识别 drive 已卸载专用 APK 的情况，避免把正常未安装状态误报为清理失败。可选 `-SoftwareRendering` 仅向本次 drive 传入软件渲染/关闭 Impeller 参数，并记录 rendering，不改变默认应用。
- `.gitattributes`：仅对 `tool/wp15_d2_linux.sh` 指定 LF，防止 Windows core.autocrlf 使重检出后的 Bash 入口失效。
- `tool/wp15_d2_linux.sh`：WSL2/Linux SDK + Xvfb，复制源码到专属临时目录，隔离 XDG 数据/配置/缓存，精确锁文件离线解析，正常 Debug 构建后启动真实 Linux 页面。记录驱动实际退出码，退出时清理自建进程组和临时目录。
- `android/app/build.gradle.kts`：仅在明确传入 `WP15_D2_DEVICE=true` 的 debug 构建增加 `.wp15d2` applicationIdSuffix；正常包、release、签名和默认行为沿用原值。

没有改 main.dart、Windows 原生代码、Store/SaveProtocol、模型、备份契约、发行脚本、依赖锁文件或公共路线图。Flutter 生成文件、缓存、AVD 和日志不提交。

## 数据与证据边界

测试直接渲染 MatrixHome、TaskDetailPanel、PlannerScreen 及生产详情/编辑/时区选择器，调用生产 `defaultDeviceTimeZoneSource()`。没有注入模拟时区 source。Android 在读取偏好前校验应用支持目录含 `com.matrixflow.app.wp15d2`；Linux 校验专属 XDG 根。使用真实 SharedPreferences 插件及磁盘重读，合成资料通过现有 `previewImport(..., 'overwrite')` / `applyImport` 导入。

合成库含板、父任务、已完成子任务、时间块和独立/关联事件，并保留任务日期、截止、提醒、象限、笔记、标签、子任务完成时间等字段。凭据端口禁用密钥写入，提醒使用 InMemoryReminderService；真实通知投递和密钥存储不属于此证据。草稿保存失败是对双槽 pointer 写入返回 false 的故障注入，未损坏真实用户资料。

四个设备场景：

1. 首页“更多 → 日程计划”，父任务详情“安排时间”，草稿失败停留原页、重试成功，创建时间块后真实磁盘 reload/reopen，重新打开编辑器。
2. Android 日程页保持打开时，宿主收到 `WP15_D2_ZONE_READY` 后将系统从 Asia/Shanghai 改为 Asia/Tokyo，等待生产通道刷新。Linux 移除/重新进入生产页面重读。随后切换显示为 America/New_York，深比较整库，除导出 timestamp 外零变化。
3. America/New_York 2026-03-08 的 23 小时轴及 gap 拒绝零写入；2026-11-01 的 25 小时轴、两种 01:00 偏移、显式选择 -05:00 保存并从磁盘重开还原。午夜结束不占次日，跨日片段均可访问，重叠时间块和事件分别编辑，日/周切换，任务字段保持不变。
4. 实际平台页面套用 320px 宽、TextScaler=3 的验收布局，自动化触控/鼠标指针事件与键盘 Enter 保存；v3 导出到临时文件、磁盘重开、清空合成偏好，再通过现有导入命令恢复。逐字段深比较全部序列化内容，并在恢复后的页面重开编辑器。

这是原生平台中的自动化输入和布局约束，未操作实体鼠标/键盘/触摸屏，未改变系统字号，未使用读屏。驱动日志 `+6` 包括 setUpAll/tearDownAll，实际业务场景为 4 个。

## 验证结果

验证日期 2026-10-01 至 2026-10-03。命令均在本工作树执行；日志在忽略目录 `build/wp15-d2/`，不能将早期失败尝试计作通过。

| 验证 | 结果与退出码 |
|---|---|
| `flutter analyze --no-pub` | No issues found，0 |
| D1 三文件 + C1/C2 五文件 + D2 picker/导航布局 | 111 通过，0 |
| 默认 `flutter test --no-pub --reporter expanded` | 1379 通过、8 跳过，0；D2 设备入口显式跳过 |
| Linux 正常主入口 `build linux --debug --no-pub` | 0，未启动 Windows 原生应用 |
| Linux / WSL2 / Xvfb，进程 TZ=Asia/Tokyo | 四场景通过，0；生产读取 identity/iana=Asia/Tokyo |
| Linux / WSL2 / Xvfb，unset TZ，系统配置 | 四场景通过，0；生产读取 identity/iana=Asia/Shanghai |
| Android 专用模拟器完整设备验收 | 四场景通过，drive/脚本均 0；真实运行中时区变更，软件渲染 |
| Android/Linux 未显式开启入口 | 两个脚本均退出 2（blocked），未启动应用 |
| Android 正常主入口 Debug 构建 | 0；aapt 确认 com.matrixflow.app，未安装正式包 |

定向回归精确命令（Windows SDK 为 `D:/Dev_SDKs/Flutter_3.32.8/bin/flutter.bat`）：

```powershell
& D:/Dev_SDKs/Flutter_3.32.8/bin/flutter.bat analyze --no-pub
& D:/Dev_SDKs/Flutter_3.32.8/bin/flutter.bat test --no-pub --reporter expanded test/wp15_d1_device_time_zone_test.dart test/wp15_d1_time_zone_change_test.dart test/wp15_d1_navigation_test.dart test/wp15_c1_schedule_layout_test.dart test/wp15_c1_planner_screen_test.dart test/wp15_c2_edit_session_test.dart test/wp15_c2_drag_test.dart test/wp15_c2_planner_editor_test.dart test/wp15_d2_zone_picker_test.dart test/wp15_d2_navigation_layout_test.dart
& D:/Dev_SDKs/Flutter_3.32.8/bin/flutter.bat test --no-pub --reporter expanded
& D:/Dev_SDKs/Flutter_3.32.8/bin/flutter.bat build apk --debug --no-pub
```

## 重跑设备入口

先用固定 Windows SDK 完成 `pub get --enforce-lockfile`，不升级依赖。Android 要求显式设备且 API >= 26（宿主使用 cmd alarm set-timezone）。关闭开关或缺少设备退出 2，设备缺失/中断/断言失败均非零，不算通过。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tool/wp15_d2_android.ps1 -Run -Device emulator-5580 -SoftwareRendering
```

先构建 opt-in APK，使用 aapt 验证身份精确为 `com.matrixflow.app.wp15d2` 后才允许 drive 安装。正式 `com.matrixflow.app` 不安装、不清理、不读取。Android 元数据为 `android-result.json`，构建/驱动日志分别为 `android-isolated-build.log` / `android-drive.log`。

Linux SDK 为 `/home/ubuntu/develop/flutter/bin/flutter`；WSL2 Ubuntu-24.04，内核 6.6.87.2，GTK3 3.24.41，Xvfb 虚拟 X11 显示。系统 `/etc/timezone` 为 Asia/Shanghai，`/etc/localtime` 链接同名 zoneinfo；系统模式 unset TZ。未修改 Linux 系统配置，也不声称 Linux 有原生时区变更推送：本轮验证进入/重新进入页面的读取边界。

```bash
GDK_BACKEND=x11 LIBGL_ALWAYS_SOFTWARE=1 \
  bash tool/wp15_d2_linux.sh --run /home/ubuntu/develop/flutter/bin/flutter Asia/Tokyo
GDK_BACKEND=x11 LIBGL_ALWAYS_SOFTWARE=1 \
  bash tool/wp15_d2_linux.sh --run /home/ubuntu/develop/flutter/bin/flutter system
```

本机 Linux 缓存缺少固定版本，因此实际调用额外设置 `WP15_D2_PUB_CACHE_SEED=/mnt/d/Dev_project/martix-wp15-d2/build/wp15-d2/pub-cache-seed.tar`，由 Windows 缓存中的锁定 package 源码/哈希/版本元数据制成，不提交该归档。也可指定完整的 package 缓存目录；seed 只复制进临时目录，解析使用 `--offline --enforce-lockfile`，再次比对所有包版本，禁止镜像缓存导致传递依赖升级。

Linux 每种模式独立记录 `linux-Asia_Tokyo.log` / `linux-system.log` 和对应 result.json。四场景完成后 integration_test 会提示 Linux 未检测到原生 integration_test plugin；本轮以 Flutter VM driver 收到完整测试结果、`WP15_D2_RESULT` 和实际退出码 0 为证据，未声称 Android instrumentation/XCTest 捕获方式。

## 清理、中断与剩余缺项

Android 专用 AVD `wp15d2`，serial `emulator-5580`，API 35 / x86_64，测试应用 `com.matrixflow.app.wp15d2`。原时区 GMT、auto_time_zone=1；验收先置 Asia/Shanghai，保持日程页打开时变更为 Asia/Tokyo。最终元数据 `liveZoneChanged=true`、`flutterExitCode=0`、`exitCode=0`、`restoredZone=GMT`、`restoredAutoZone=1`。另用 ADB 独立复核原值；drive 已卸载专用 APK，pm list packages 确认不存在，syntheticDataCleared=package-not-installed。只关闭自建 emulator-5580，未操作其他设备或正常包。宿主 emulator 35.2.10 的 headless QEMU 在 GPU 渲染时出现 Windows Application Error / 0xc0000005，实际进程退出 -1073741819，设备驱动退出 1。ANGLE 选项在本宿主回退到 SwiftShader；最终使用 Flutter 软件渲染规避宿主崩溃，实际仍渲染 Android 原生窗口和生产页面，不将此作为默认 GPU 路径稳定性证据。早期设备消失导致恢复失败的尝试退出非零；再次启动专用 AVD 后已先恢复原 GMT、auto_time_zone=1，再开始最终验收。失败日志未当作有效通过。Linux 临时 XDG、合成备份和自建显示/应用进程由退出处理清理。用于重跑的忽略目录 AVD/日志/精确缓存 seed 保留，不包含用户库或个人截图。

本批未连接真机；Android 真机完整 D2、Linux 实体桌面、Windows 原生界面/系统时区变更、实体输入设备、系统大字号和读屏仍未验收。Windows 原生验收由并行包独占，本包没有启动 Windows 应用或修改 Windows 系统时区。未覆盖 Linux 运行中修改 /etc 配置后恢复刷新、Android API<26 的完整 D2、所有时区/分卷规模组合或旧版本回退提示。公共文档和剩余 WP15 门禁由集成端收口。本包不 push、不合并其他包。
