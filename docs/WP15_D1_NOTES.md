# WP15-D1：日程入口与设备时区

基线：`0c36b36da336f4c6551ccf93c49b567cde51f414`。工作树：`D:\Dev_project\martix-wp15-d1`，分支：`codex/wp15-d1`。本包只接入首页/父任务入口与设备 IANA 时区发现、刷新和显示时区切换，复用 A1/A2/C1/C2 已有模型、事务与命令；不代表 WP15-D 或整项 WP15 已验收，公共导航文档与全量/云端门禁由集成端统一处理。

## 接入与改动边界

新增 `lib/platform/`：

- `device_time_zone.dart`：平台身份读取与解析（Android/Windows 通道源、Linux 系统配置文件源、变更事件流）、`DeviceTimeZoneProblem{unavailable,unmapped,invalid}`、IANA 校验与选择器候选列表。
- `device_time_zone_controller.dart`：显示时区状态机（设备值、用户选择、恢复/平台事件重读、仅在实际变化时通知）。
- `device_time_zone_picker.dart`：合法 IANA 选择器与问题文案（`scheduleZoneProblemText`）。
- `windows_time_zone_map.dart`：Unicode CLDR release-47 `windowsZones.xml` territory="001" 全量 139 条映射，文件头记录来源 URL 与源文件 sha256（`39714d7a…cbfcba`）。

修改：`lib/screens/matrix_screen.dart`（“更多”新增日程入口，沿用 `_protectDetailDraft`）、`lib/screens/planner_screen.dart`（可注入时区控制器、未知时区状态、父任务预选并自动新建时间块、显示时区/设备时区标签与页内切换、`openPlannerScreen` 统一入口）、`lib/widgets/task_detail_panel.dart`（父任务次级“安排时间”，窄屏先关面板再进入，可注入回调）、`lib/l10n.dart` 三语言 `schedule*` 新增文案、Android `MainActivity.kt` + 新增 `DeviceTimeZoneBridge.kt`、Windows `windows/runner/flutter_window.{h,cpp}`。

未修改：`lib/main.dart`、Store/SaveProtocol、日程模型/时间规则、备份与迁移、导入预检、截图导入/OCR、平台 CMake/Gradle 构建配置、发行脚本、公共路线图；`pubspec.yaml`/`pubspec.lock` 未动（复用现有 `timezone` 包与既有通道模式，无新依赖）。Linux runner 未改动：时区从系统配置读取，GTK/GLib 没有标准时区变更信号。

## 用户流程

- 首页“更多”第一项为“日程计划”（截图导入入口保留在其下）。离开未保存详情草稿时沿用现有离开保护。
- 父任务详情新增次级“安排时间”：先把待保存草稿就地写入（不丢弃），保存失败留在原页面并显示既有错误文案；窄屏先关闭详情面板再进入日程；随后自动打开该父任务的新时间块编辑器，关联已预选，起止仍由用户明确选择（不预填结束时间、不加跨度上限、不动提醒）。子任务行与一级任务输入没有日程入口。
- 日程页显示 `设备时区: …`（跟随设备）或 `显示时区: …`（用户已选择），并提供“切换显示时区”。未知时区时整页只显示原因与选择入口，不渲染网格。

## 设备时区服务

- 身份来源：Android `TimeZone.getDefault().id`（本身就是 IANA）；Windows `GetDynamicTimeZoneInformation().TimeZoneKeyName`（Windows 键名，经固定 CLDR 表翻译）；Linux 依次读 `TZ`（含 `:Zone`、zoneinfo 路径、POSIX 规则）→ `/etc/timezone` → `/etc/localtime` 链接目标。
- 不用当前 UTC 偏移或语言猜城市：映射缺失记 `unmapped`、读取失败/平台无应答记 `unavailable`、非 IANA 记 `invalid`，三者都进入用户选择；`/etc/localtime` 是副本文件时无法命名时区，同样进入选择而不是按偏移推断。UTC 不会被当作设备时区。
- 刷新：进入日程页时重读一次；app 恢复（`AppLifecycleState.resumed`）、Android `ACTION_TIMEZONE_CHANGED`、Windows `WM_SETTINGCHANGE`/`WM_TIMECHANGE` 后重读（Windows 无公开的 SPI 时区常量，改为转发设置变更，由 Dart 侧比较身份后才重绘）。Linux 无标准桌面通知，靠恢复/重开刷新。
- 只改视图：切换显示时区后 `startAt/endAt/timeZoneId`、`plannedDate/deadline/reminder/象限` 一律不变（测试比对整库 JSON）。已打开的编辑表单保留其记录时区、墙上时间与 DST 候选/偏移，后台时区变化不会静默重解释输入。
- 用户选择是会话级内存状态：持久化需要改设置模型与 SaveProtocol（均不在本包归属），因此不做库内保存。

## 平台实现

- Android：`DeviceTimeZoneBridge` 响应 `matrixflow/device_time_zone` 的 `systemZone`，注册 `ACTION_TIMEZONE_CHANGED`（API 33+ 用 `RECEIVER_NOT_EXPORTED`），`onDestroy` 反注册并清空通道处理器。
- Windows：`flutter_window.cpp` 新增同名通道（`{platform:"windows", identity:TimeZoneKeyName}`，UTF-8 转换），在 `WM_SETTINGCHANGE`/`WM_TIMECHANGE` 上推送 `onTimeZoneChanged`，`OnDestroy` 释放通道。
- 未使用 FFI 直读注册表，也未新增依赖。

## 自动化验证

SDK：`D:/Dev_SDKs/Flutter_3.32.8/bin/flutter.bat`。

```powershell
& D:/Dev_SDKs/Flutter_3.32.8/bin/flutter.bat test --no-pub test/wp15_d1_device_time_zone_test.dart test/wp15_d1_time_zone_change_test.dart test/wp15_d1_navigation_test.dart --reporter expanded
& D:/Dev_SDKs/Flutter_3.32.8/bin/flutter.bat test --no-pub <33 个定向+受影响回归文件> --reporter compact
& D:/Dev_SDKs/Flutter_3.32.8/bin/flutter.bat analyze --no-pub
& D:/Dev_SDKs/Flutter_3.32.8/bin/flutter.bat build windows --debug
& D:/Dev_SDKs/Flutter_3.32.8/bin/flutter.bat build apk --debug
```

- 本包新增测试 3 个文件 **39 项通过，exit 0**：`wp15_d1_device_time_zone_test.dart`（22：身份解析/映射/校验/Linux 配置 8 例/通道源 3 例，含 139 条映射全部落在内置时区库）、`wp15_d1_time_zone_change_test.dart`（7：控制器状态、用户选择优先级、平台事件与恢复重读、页面重投影且零改写、打开中的表单不被重解释、DST gap/fold 候选保持）、`wp15_d1_navigation_test.dart`（10：更多菜单入口、无时区时的选择流程、设备时区直出、父任务“安排时间”预选时间块、草稿先保存、保存失败不跳转、目标父任务删除提示、恢复态提示、子任务无入口、320px×3 倍字号）。
- 定向 + 受影响回归 **33 个文件 446 项通过，exit 0**（含 WP15 C1/C2/A/B 相关 12 个文件与首页/详情/UX/OS 回归 21 个文件）。
- `flutter analyze --no-pub`：**No issues found，exit 0**。
- 构建：`flutter build windows --debug` exit 0（`build\windows\x64\runner\Debug\compoise.exe`）；`flutter build apk --debug` exit 0。

## 真实平台证据

- **Windows 桌面（真实通道）**：`flutter test integration_test/<临时探针> -d windows` 打印 `D1_REAL_DEVICE platform=windows identity=China Standard Time iana=Asia/Shanghai problem=null`；本机注册表 `TimeZoneKeyName` 同为 `China Standard Time`，查表得 `Asia/Shanghai` 一致。构建产物启动 20s 存活后正常关闭（临时探针文件未提交）。
- **Android 模拟器（API 23，走 API<33 广播分支）**：把系统时区置为 `Asia/Tokyo` 后探针打印 `platform=android identity=Asia/Tokyo iana=Asia/Tokyo problem=null`（探针前系统为 GMT，证明读的是实时系统时区）。已把模拟器时区还原为 GMT。
- **Android 真机（Android 16 / SDK 36，走 API 33+ `RECEIVER_NOT_EXPORTED` 分支）**：无头自动化安装正常 debug APK 后，首页“更多”第一项为“日程计划”，点击进入日程页，界面节点显示 `设备时区: Asia/Shanghai`、`切换显示时区`、日视图 `24.0 小时` 与 `UTC+08:00` 时钟轴——即真机设备时区发现端到端可用（该探针运行被中断，未在真机打印通道原始值；真机证据为界面级）。
- 说明：真机第一次安装的是集成测试 APK（其 Dart 入口是测试文件，不构建界面），因此打开是白屏；随后重新安装正常 debug APK 恢复正常，此现象与本包代码无关。

## 未验收

- Linux 实机未测（无 Linux 主机）：`TZ`/`/etc/timezone`/`/etc/localtime` 仅由注入文件的单元测试覆盖；Linux runner 未改，靠恢复/重开刷新。
- 运行中“真实”改变系统时区（Android 广播、Windows `WM_SETTINGCHANGE`）只在测试中注入事件验证，未在真机/桌面开着日程页时切换系统时区实测；真机 DST gap/fold 也未实测。
- Windows 桌面上的时区界面路径未做 GUI 自动化（仅验证通道读取与应用启动）；触控/鼠标拖动精度、实体键盘、原生读屏、超大字体实机表现未测。
- 全量测试、云端检查与公共导航文档更新由集成端统一执行；本包不声明 WP15-D 或 WP15 完成。
