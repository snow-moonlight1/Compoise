# WP15-D3：Windows 原生日程页面与时区通知验收

日期：2026-10-03；工作树 `D:/Dev_project/martix-wp15-d3`；分支 `codex/wp15-d3`。共同基线为 `5fb4592ccc10cdcc1698e27f68d2367a3d83cf18`。先应用 D2 原提交 `ae663e27e217e208680cb7adce7474306187a948`，在本分支产生前置提交 `7c9c084ebb2174def5002948eaaf62ccedd56061`；D3 自身另作一份提交，完整 SHA 随交接给出。验收日志的 revision 是上述前置 SHA，dirty=true，表示运行本包提交前的源码；没有把旧树结果算作本轮结果。

固定 Flutter 3.32.8 / Dart 3.8.1，Windows SDK 位于 `D:/Dev_SDKs/Flutter_3.32.8`。实测宿主版本为 Windows NT 10.0.26200.0，脚本运行于 PowerShell 7.6.5。依赖沿用原锁文件，`pub get --enforce-lockfile` exit 0。

## 实现与隔离

- `test/wp15_d3_device_test.dart` 复用 D2 合成任务、日程和四个业务场景，增加 Windows 开放草稿/通知/语义键盘场景，以及删除/真实损坏库恢复禁写场景。直接渲染生产 MatrixHome、TaskDetailPanel、PlannerScreen、详情、编辑和时区选择器。默认明确跳过，仅 `WP15_D3_DEVICE=true` 才初始化设备 binding。
- `test/wp15_d3_support.dart` 在任何资料 IO 前核对 native/runtime 门、PID、GUID、规范路径和专用 desktop。锁定版本插件的测试接缝只改实际文件目录；shared_preferences_windows 和 path_provider_windows 仍执行真实文件 IO。库重开和备份重开均深比较序列化内容。凭据使用禁止非空写入的实现，提醒使用 InMemoryReminderService。
- `test/wp15_d3_device_driver.dart` 连接本次 Windows 进程的 loopback VM service，验证 commit、PID、根目录和命名空间后写回结果。要求实际 driver exit 0；结果标记本身不算通过。
- `windows/runner/CMakeLists.txt` 同时要求 native 环境 `WP15_D3_DEVICE_BUILD=1` 和 Dart define `WP15_D3_DEVICE=true`；仅有一个即拒绝，D3/U2 诊断混用也拒绝。普通构建不编译诊断通道、查询注入和专用启动分支。
- `windows/runner/wp15_d3_validation.*` 要求运行时 `WP15_D3_RUN=1`、严格小写 GUID、已存在且规范化的 OS-temp 直接子目录 `wp15-d3-device-<GUID>`。Win32 文件句柄解析实际路径，拒绝相对路径、点组件、重解析到其他位置及非专属根；使用 `Local\\Compoise.WP15D3.<GUID>` mutex。
- 诊断线程在 COM、Flutter 和应用窗口创建前进入自己创建的 `wp15-d3-<GUID>` Win32 desktop。比较 input desktop 与自己的 desktop，未调用 SwitchDesktop、SetForegroundWindow 或系统输入注入。实际 HWND 和 Flutter 渲染存在于该专用 desktop，内部 touch/mouse/Tab/Enter 不驱动用户设备；截图来自本次 Flutter RepaintBoundary，不是用户桌面截图。Windows 线程与 desktop 的关系参见 [Microsoft 文档](https://learn.microsoft.com/en-us/windows/win32/winstation/thread-connection-to-a-desktop)。
- `main.cpp` 仅增加诊断隔离门；普通单实例分支保持原逻辑。退出和创建失败均保留 U2 的派生窗口/引擎销毁 → CoUninitialize 顺序，然后释放 D3 资源。正常 single_instance.cpp、U2 启动/迁移/凭据逻辑未改。
- `flutter_window.*` 的诊断通道记录真实查询/窗口消息次数；查询替换仅作用于自己的诊断进程。向自己的 HWND 同步发送 WM_SETTINGCHANGE/WM_TIMECHANGE，生产时区通道继续处理重读。恢复用明确标注的 flutter/lifecycle 注入。WM_SETTINGCHANGE 的系统消息语义参见 [Microsoft 文档](https://learn.microsoft.com/en-us/windows/win32/winmsg/wm-settingchange)。
- `tool/wp15_d3_windows.ps1` 默认关闭，每次显式运行都重新构建，核对目标/native 门/产品身份，跟踪 PID、路径、开始时间和实际退出码。通过自己的 desktop 枚举仅关闭自有窗口；超时强制清理标记失败。成功和失败证据均先保留，再校验并清理精确 temp 子目录，恢复本次进程环境。另有默认关闭的 runtime/build gate 验证脚本。

本包没有修改 Store/SaveProtocol、备份模型、pubspec、main.dart、OCR、Android/Linux D2 脚本、发行 CI 或公共路线图。D2 实测布局修复由前置提交提供。

## 原生矩阵与真实/注入边界

最终六个业务场景全部通过；日志的 +8 包含 setUpAll/tearDownAll，并非八个业务场景。

| 场景 | 本轮证据 |
| --- | --- |
| 首页 更多→日程、父任务安排、草稿失败保护、创建与磁盘重开 | 生产页面与真实 Windows 插件文件 IO；指针提交失败为显式测试注入 |
| 设备时区读取、显示时区只重投影、消息重读、恢复重读 | 初始真实 Win32 `China Standard Time` → `Asia/Shanghai`；随后 Tokyo/Eastern/China 查询结果与自己的窗口消息、框架恢复为进程内注入 |
| DST gap/fold、23/25 小时、午夜边界、跨日与重叠 | 真实生产页面/固定时区数据库/显式偏移选择；保存和重开断言 |
| 实际 320 logical px 窗口、3x 文字、内部鼠标/触摸/Enter、v3 导出和重开 | 原生客户区按当前 DPR 调整并核对实际 view 宽度；TextScaler 仅在验收页面内设 3x；全字段深比较与本页 PNG |
| 开放 fold 草稿经过设置/时间消息与恢复、Tab/Enter、保存语义 | 矩阵累计 20 次真实通道查询、各 2 次 WM_SETTINGCHANGE/WM_TIMECHANGE；草稿标题/时间及 -240/-300 分支保持；semantic tap 与焦点遍历断言 |
| 删除取消/确认/重开、损坏库恢复禁止写入 | 合成损坏实际偏好文件，真实 Store 恢复锁；无新增/编辑控件，内部 Enter 后原文件值不变 |

显示时区切换与刷新深比较 startAt/endAt/timeZoneId，以及父任务 plannedDate/deadline/reminder/象限、子任务和其他持久化字段，保持零业务改写。手动显示时区不会被设备查询变化覆盖；开放编辑会话继续保留原记录时区与 DST 候选。

最终自有 PID 为 `47460`，命名空间 `4c101c35-afcf-4f44-82be-91c4bae68d2e`。最终 status：windowVisible=true、privateDesktop=true、foregroundOwned=false、queryInjected=false。build/driver/native/script 的实际退出码均为 0，无超时强制清理、进程残留或 temp 库残留。运行前后宿主全局时区均为 China Standard Time；没有执行全局切换。

## 命令、退出码与证据

根目录：`D:/Dev_project/martix-wp15-d3/build/wp15-d3`。日志、截图、缓存、生成文件和二进制均不提交。

| 命令或检查 | 结果 | 证据 |
| --- | --- | --- |
| `flutter analyze --no-pub` | 无问题，exit 0 | analyze.log |
| D1/C2/D2/D3 + U2 定向 `flutter test --no-pub` | 101 通过 / 2 默认设备入口跳过，exit 0 | targeted.log |
| `flutter test --no-pub --reporter expanded` | 1399 通过 / 9 跳过，exit 0 | full.log |
| 三个 D3 脚本不带 `-Run` | 均 blocked exit 2 | 实际子进程退出码检查；不构建、不启动应用 |
| `tool/wp15_d3_build_gates.ps1 -Run` | native-only / Dart-only / D3+U2 各按预期构建拒绝 exit 1；脚本 exit 0 | build-gates.log、build-gates/result.json |
| `tool/wp15_d3_windows.ps1 -Run` | 六场景，build/driver/native/script exit 0 | device-build.log、native-stdout.log、driver.log、windows-result.json |
| `tool/wp15_d3_gates.ps1 -Run` | 9 个无效运行门各 native exit 2，无引擎输出/残留；脚本 exit 0 | runtime-gates.log、gates/runtime-result.json |
| 最后 `flutter build windows --debug --no-pub -t lib/main.dart`，不带诊断环境/define | exit 0，正常目标、Dart/native 门均关闭 | normal-build.log、normal-result.json |

运行门九项：缺少 run、缺少 GUID、非法 GUID、缺少 root、OS-temp 根本身、工作树根、GUID 不匹配、点组件、同命名空间 mutex 已存在。负向脚本只允许启动刚通过原生矩阵且摘要相同的诊断二进制；正常重建之后它会拒绝旧诊断证明。

最终设备证据目录为 `evidence/4c101c35-afcf-4f44-82be-91c4bae68d2e/`，包含 driver-result.json 和 planner-narrow-3x.png。图片为保存后滚动到日程卡片的生产页面。
诊断 exe SHA-256：`54d995a5acd2c6edaa8815f551d41640b96b3ab7f6e6a873bd6136b7b9a62418`；
对应 Dart kernel：`a6fcfd59b8c1d54503e5e8d8db6910343bcf49e5fa8e3666a9f46d38a4d36bf8`。
最后普通 Debug exe SHA-256：`b54c97648bf329708163c57d298d94528e2debda79dad657caa7e6f08ef3dd8e`，不是诊断包。

复现顺序（固定 SDK，先在自己执行树解析锁文件）：

```powershell
./tool/wp15_d3_build_gates.ps1 -Run
./tool/wp15_d3_windows.ps1 -Run
./tool/wp15_d3_gates.ps1 -Run
# 最后恢复正常产物；普通包只构建，不启动真实用户库。
Remove-Item Env:WP15_D3_DEVICE_BUILD -ErrorAction SilentlyContinue
Remove-Item Env:WP28_U2_HARNESS_BUILD -ErrorAction SilentlyContinue
D:/Dev_SDKs/Flutter_3.32.8/bin/flutter.bat build windows --debug --no-pub -t lib/main.dart
```

定向测试包含 wp15_d1_device_time_zone、wp15_d1_navigation、wp15_d1_time_zone_change、wp15_c2_edit_session、wp15_c2_drag、wp15_c2_planner_editor、wp15_d2_navigation_layout、wp15_d2_zone_picker、wp15_d2_device、wp15_d3_device 和 wp28_u2_credentials 的 `test/*_test.dart` 文件。

## 修复前失败与未验收

早期诊断构建曾因不存在的 string_codec 头文件退出 1，已改用当前 SDK 的 BinaryMessenger 字节接口。初轮窗口设置异步投递失败、草稿控件定位类型错误、foregroundOwned=true，均按失败记录；改为同步窗口消息、定位 EditableText、并在窗口创建前分配专用 desktop。随后日志重定向的缓冲/共享问题使运行器无法读取 VM service，关闭当次核对过的自有窗口后 native exit 0、脚本非零，该轮不算通过；现改用直接文件重定向并持有原生进程句柄。第五场景还曾重复点击已完成的预检，修复测试步骤后通过。静态分析的两项未使用导入也已清除。没有削弱业务、焦点隔离或退出断言来得到通过。

Windows integration_test 未注册原生 instrumentation plugin 的警告仍存在；本包使用 Dart VM driver 收到的标准测试结果、原生 status、实际进程退出和磁盘断言，明确不称为 Windows instrumentation 测试。

未验收：隔离 Windows VM 中真实全局时区切换及系统设置广播、真实前后台恢复、物理鼠标/键盘、系统字号/DPI 全局切换、Windows 读屏端到端、正常用户资料和凭据升级、Release/签名/安装/发布。U2 独立 12 场景/52 进程升级矩阵本轮未重跑；本轮 U2 回归是其定向/默认测试及保留顺序后的 D3 原生引擎退出。WP15 仍需按这些边界继续验收。
