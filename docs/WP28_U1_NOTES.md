# WP28-U1：Windows 历史目录接纳

基线：`0c36b36da336f4c6551ccf93c49b567cde51f414`。分支：`codex/wp28-u1`。
工作树：`C:/Users/20214/.codex/worktrees/wp28-u1/martix`。
本包保留 `Compoise/Compoise` 身份，不修改 runner、构建配置、模型、导入规则或快照格式。

## 启动顺序

`WidgetsFlutterBinding` → Windows window manager → 安装现有单实例/通知参数处理 →
Windows 升级启动页检查/复制 → 提醒服务 `init` → 原有 `MatrixFlowApp` / Store `init`。
创建 ReminderService 对象本身不打开首选项。升级未完成时不创建 Store、不初始化提醒持久化。
升级页面关闭按钮只在 Store 打开前销毁窗口；进入应用后仍走原有退出、保存、销毁顺序。
单实例的启动参数接收与后续窗口恢复/通知 payload 分发接线保持原样。

## 插件与目录证据

检查的是 lockfile 对应的真实插件源码，而不是推测文件格式：

- `shared_preferences_windows 2.4.1`：`shared_preferences.json` 为 JSON 对象；旧 API 键有 `flutter.` 前缀。
  插件会将零字节或非对象 JSON 当作空首选项，因此本包在插件缓存建立前阻止这种读取。
- `path_provider_windows 2.3.0`：Windows Known Folder `RoamingAppData` 加 exe 的 CompanyName/ProductName。
  生产路径解析直接使用该插件的 Known Folder FFI 方法，不调用会先建应用目录的 SupportPath 方法。
  为绕开公共 conditional export 缺少常量/可空类型的 analyzer stub，读取此锁定版本的两个 `lib/src` 接口。
  当前身份仍由 OS26 固定为 `Compoise/Compoise`。
- `flutter_secure_storage_windows 4.1.0`：当前 `flutter_secure_storage.dat` 是用户 DPAPI 保护的 JSON；
  兼容 C++ 路径还涉及 AES-GCM `.secure` 文件及 Windows Credential Manager 中的 AES 密钥/旧条目。
  当前 `WindowsOptions` 默认关闭 backward compatibility。调用旧版的自动迁移接口可能写入或删除源文件。

本包不解密、不复制、不删除旧加密凭据文件，也不枚举系统凭据。仅检查旧文件名。
合成 DPAPI 测试验证了真实插件在隔离源目录的写入/读回，以及用户在隔离目标目录重新配置后的写入/读回；
这是重新配置证据，不是加密凭据迁移成功的声明。

## 接纳、提交与恢复

源：`<RoamingAppData>/com.matrixflow/MatrixFlow AI`。
目标：`<RoamingAppData>/Compoise/Compoise`。

1. 目标目录中存在任何用户资料即优先使用目标。有效空库 `{}`、已有空任务集合、坏 pointer/槽、
   不可读目标文件、仅凭据文件等均不被旧库覆盖或自动合并。目标仅为空目录时允许接纳。
2. 验证绝对、规范路径；逐层检查实体类型与真实路径，拒绝链接、junction/别名、异常源文件和目标凭据文件别名。
   目录遍历不跟随链接。测试路径、读写、提交、故障均可注入。
3. 源文件始终只读。读出整个首选项 envelope，在目标公司目录下创建本次拥有的随机临时目录；
   独占创建临时文件，写入并 flush，逐字节读回验证，再检查源未发生变化。
4. 提交点是同卷 `MoveFileExW(MOVEFILE_WRITE_THROUGH)` 发布单个 `shared_preferences.json`。
   不设置 `REPLACE_EXISTING` 或 `COPY_ALLOWED`；不存在先检查后用可覆盖 rename 的回退。
   提交前再次检查目标；提交时新库出现由操作系统拒绝覆盖，并重新采用目标的启动/恢复状态。
   提交返回前中断或返回后抛错均可重试；已发布目标优先。flush/队列完成不宣称断电物理持久性。
5. 清理仅针对本次创建且仍在范围内的临时文件/目录，并再次检查真实路径；不递归清理。
   旧中断残留及未知文件不扫除，位于目标用户目录之外，不阻碍重试。清理失败不回滚已提交库。
6. 无旧加密文件时首选项逐字节复制；有旧加密文件时只在外层 envelope 添加
   `flutter.matrixflow-upgrade-credentials-required` 布尔提示，原始键值/槽字符串不改。
   提示与库共用同一提交点，提交后崩溃也不会丢失重新配置提示。

`SaveProtocol.readCommitted` 是从原 `load` 抽取的只读验证；`load` 仍使用同一实现。
不尝试用另一槽或镜像替换坏 pointer，不补读旧槽缺失的可选 schedule 镜像。
正常旧镜像、双槽和合法空库交给原 Store 规则读取/迁移；任务、子任务、看板、配置、plannedDate 和日程不重写模型。
可解析 envelope 的坏 pointer/槽会先提示，然后进入原恢复页面；坏任务/日程/配置由 Store 进入相同恢复锁。
为使坏日程的恢复页面可显示，最小补充 `StartupRecoveryScreen` 的一行 schedule 标签映射，复用现有三语 `scheduleTitle`。
没有修改恢复的导出/丢弃规则。

不可解析 envelope 的源或目标停在三语重试/手动恢复说明页面，保留原文且不打开默认空库。
说明区分首选项恢复副本与可导入备份：先保留私有副本、用已知完整副本恢复并重试，之后用原设置页导入并核对预览。
旧明文配置仍须经 Store 既有安全写入、读回验证和槽/镜像 scrub 门禁；失败保留可重试数据。
加密凭据提示保守地保留在首选项中，后续启动仍可看到；本包不在未验证 Store 前写盘清除此提示。

## 验证与边界

固定工具链：Flutter 3.32.8 / Dart 3.8.1，framework `edada7c56e`，engine `ef0cd00091`。
所有测试与原生探针均使用临时目录和合成数据；没有打开真实用户库或真实 API 密钥。
测试在 Windows 主机执行；DPAPI 用 `useBackwardCompatibility=false`，不访问系统旧凭据。

相关验证命令（同一固定 SDK，使用串行与 2 分钟 IO 超时）：

```powershell
flutter test --no-pub --concurrency=1 --timeout=2m test/wp28_u1_upgrade_test.dart test/wp28_u1_startup_test.dart test/wp28_u1_windows_plugin_test.dart test/os05_startup_recovery_test.dart test/os06_os07_transaction_test.dart test/os08_os09_credential_test.dart test/os16_single_instance_test.dart test/os15_desktop_exit_test.dart test/os20_store_boundary_test.dart test/os26_release_test.dart test/wp15_schedule_store_test.dart --reporter expanded
flutter test --no-pub --concurrency=1 --timeout=2m test/wp28_u1_boundaries_test.dart --reporter expanded
flutter analyze --no-pub
flutter build windows --debug --no-pub -t test/wp28_u1_windows_probe.dart
```

早期批次发现一个清理断言错误：提交前失败可留下合法空目标目录，应该断言没有目标库/本次临时文件。
修正了该断言。与初次 Windows 原生构建并发的默认 30 秒批次有两个 IO/DPAPI 超时；
超时后的 teardown 还导致未结束的用例再报失败。没有通过吞掉异常来让测试通过，最终改用上述串行复核。

原生探针仅接受 OS 临时目录下预建的 `wp28-u1-device-*` 目录，并必须通过 `WP28_U1_PROBE_ROOT` 注入。
它保留真实 exe 元数据，将 Known Folder 根注入临时目录，核对真实 path_provider 生成的 `Compoise/Compoise` 路径；
使用生产应用/Store、真实首选项插件和内存合成凭据/Noop 提醒。JSON 探针结果只存临时目录，不提交生成物。

## 最终验收记录（2026-10-01）

| 验证 | 数量/结果 | 退出码 |
|---|---|---|
| 升级、三语页面、真实 Windows 插件及 OS05/06/07/08/09/15/16/20/26、WP15 日程相关回归 | 144 项全部通过，含 56 项新增测试 | 0 |
| 补充路径/临时文件/清理/当前凭据别名边界 | 7 项全部通过 | 0 |
| 合计 | 151 项通过，新增 63 项；未执行全量 | 0 |
| `flutter analyze --no-pub` | 无问题（新增边界文件后再复核） | 0 |
| Windows debug 原生探针构建 | 固定 SDK 构建成功，两次构建均成功 | 0 |
| 原生首次启动 | `status=migrated`，`passed=true`，exe 路径匹配；任务=1、日程=1，子任务/plannedDate 保留，源字节不变 | 首次 PowerShell harness 因 45 秒退出超时返回 1；不把它记作正常退出通过 |
| 原生重开 | `status=currentProfile`，`passed=true`，exe 路径匹配；同一合成资料再次保留，源字节不变；进程在超时内退出 | PowerShell harness 0；未单独记录 native ExitCode |

补充边界测试最初的别名用例因注入器使用不同 Windows 路径分隔符而没有触发故障；
改为规范路径比较后，7 项复核全部通过。未为此放宽生产路径检查。
原生首次报告证明了启动成功，退出阶段超时另行保留为局限；检查与尝试结束的仅是本次合成探针进程。
首次探针 PID 54968 的强制清理返回 Windows `Access is denied`，进程列表仍留有其条目；未能确认该条目已清除。
两份报告/日志留在同一个 OS 临时合成目录，未提交；正文只记录字段核验，不包含库原文或凭据。

未验收：生产资料升级、跨账户/跨设备加密凭据迁移、真实通知投递、断电物理持久性、完整发行构建与全量/云端测试。
通知激活、退出保存及身份的相关回归由上述 OS16/OS15/OS26 覆盖；探针不会把合成通知证据描述为真实投递证据。
本包不代表 WP28 全部完成；没有推送、tag、签名或发布。
