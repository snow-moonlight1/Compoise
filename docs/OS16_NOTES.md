# OS16 实施记录

## 基线与范围

- 基线：`0aec23f176a15eae398dbf292086e6827cea74da`
- 分支：`os16-single-instance`
- worktree：`D:\Dev_project\martix-wt-os16`
- 只实施 OS16。未开始 OS18–OS23、OS26、OS27，也未改设置页、三语字典、发行 workflow、打包脚本或 Android release 配置。
- 未修改 `storage.dart`。第二个进程在进入 Flutter 和任务库之前退出，因此没有另加 Store 文件锁，也没有收口 OS20 的命令边界。

## 跨文件说明

集成时需要知道这两处不在 runner 目录内，但是单实例入口所必需：

- `matrixflow-native/lib/main.dart`：启动时安装单实例监听。`main` 的参数改为可选，集成测试里的 `app.main()` 仍可无参调用。
- `matrixflow-native/lib/services/reminder_service.dart`：只新增 `acceptExternalActivation`，把后启动传来的任务参数放进现有通知 payload 队列。未改排程、账本或设置文案。

## 修复前证据

固定 SDK `D:\Dev_SDKs\Flutter_3.32.8`。先用未加闸门的 Debug runner 构建 `tool/os16_windows_instance_smoke.dart`。探针要求 `MATRIXFLOW_OS16_DATA_DIR`，只写该目录；不打开 SharedPreferences、凭据存储或生产通知激活器。开始前没有名为 `matrixflow_native.exe` 的进程。

两次启动间隔约 0.5 秒，读写之间重叠 1500ms，隔离文件模拟 `shared_preferences_windows` 的整文件覆盖：

- 两个进程都进入 Dart，都报告 `NO_SINGLE_INSTANCE_CHANNEL`，都写下 `WRITER`（pid 62548、57284）。
- 两者都读到 `tasks=[]`。先写入 `os16-task-a`，后写入 `os16-task-b`。
- 最终 `library.json` 只剩 `{"tasks":["os16-task-b"]}`，`os16-task-a` 丢失。
- 第二次启动带有 `--matrixflow-notification-payload=...os16-from-second...`。首进程报告里没有 `FORWARDED`。

因此竞争成立：同一用户的两次启动可以同时成为写入者，后一次整份覆盖会丢掉前一次的任务，启动参数也不会交给首实例。

生产任务库路径由代码确定，本轮没有打开该文件：`%APPDATA%\com.matrixflow\MatrixFlow AI\shared_preferences.json`。只读注册表里，`HKCU\Software\Classes\AppUserModelId\MatrixFlow.MatrixFlowApp.1.0` 的 `CustomActivator` 指向 `{69a03975-2989-4d05-b778-5e824707612f}`，对应 `CLSID` 键不存在，插件源码也没有写 `LocalServer32`。应用已在运行时，通知点击走进程内 COM，不会因此再起一个进程；应用未运行时，当前注册方式不会把进程拉起来。

## 实现

- 首进程在创建 Flutter 窗口之前取得当前用户 SID，创建 `Global\MatrixFlow.SingleInstance.<SID>`，并用只允许该用户的 DACL 创建 `\\.\pipe\MatrixFlow.SingleInstance.<SID>`。管道拒绝远程客户端。
- 后进程发现互斥量已存在时，把本次命令行转给管道，然后自行退出。它不按进程名结束任何进程。转发成功的退出码是 0；无法转交时退出码是 2，并提示已有实例无法接收，不打开任务库。
- 首实例尚在启动时，管道已经在监听。后进程最多等待约 30 秒。参数先排队，Dart 调用 `listen` 时取走；窗口句柄出现后再激活。
- 激活时，最小化窗口用 `SW_RESTORE`，托盘隐藏用的 `SW_HIDE` 则重新 `SW_SHOW`，并尝试把窗口放到前台。同一会话里，后进程在自己仍持有前台权时也会激活该窗口。
- 带 `--matrixflow-notification-payload=` 的参数（原始 JSON 或百分号编码）解析为现有 `ReminderPayload`，交给 `acceptExternalActivation`。没有任务 id 时只恢复窗口。
- 进程退出时操作系统释放互斥量和管道。异常终止后，下一次启动可以成为新的写入者。窗口开始销毁后，管道对后续转发回答忙，避免把参数交给正在退出的实例。
- 若当前进程没有 `SeCreateGlobalPrivilege`，退到会话本地互斥量，但仍用同一条按用户 SID 命名的管道做跨会话互斥。本机实际拿到的是 `per-user-global`，这条退路没有走到。
- 不同 Windows 用户使用不同 SID，互斥量和管道都不共享，任务库仍在各自的用户配置目录。同一用户的另一个会话可以转发参数，但不能把另一个会话桌面上的窗口调到前台。

## 修复后证据

仍使用隔离目录和上述 Debug smoke，不读取用户任务库。第二次进程的退出码都是 0。作用域报告均为 `per-user-global`。

- 顺序启动：首进程只写入 `os16-task-a`。后进程没有 `WRITER` 记录。首进程收到 `FORWARDED ... os16-from-second`。库文件仍只有 `os16-task-a`。
- 同时启动：后进程在首进程执行 `listen` 之前已经把参数送入队列，`LISTEN` 的返回值里包含通知参数。库文件只有先成为主实例的那一个任务。结束时只有一个本构建进程。
- 窗口就绪后隐藏：`COMMAND_HIDE hidden=true`，随后 `visible=false`。后启动把它恢复为 `visible=true`，并带回通知参数。这是托盘隐藏使用的同一条 `SW_HIDE` 通道；没有另点真实托盘菜单。
- 最小化：就绪时 `minimized=true`。后启动后的记录是 `visible=true minimized=false`。
- 异常退出：确认路径属于本 worktree 的 Debug 构建后，结束 pid 37384。新进程 pid 14124 成为写入者，读到原来的 `os16-before-kill` 并追加 `os16-after-kill`。锁没有残留。

验收结束时，没有残留的本构建进程，也没有其他 `matrixflow_native.exe`。

## 自动化与构建

- OS16 专项：`flutter test --no-pub test\os16_single_instance_test.dart`：6/6。
- 默认全量：`flutter test --no-pub`：501/501。
- 静态分析：`flutter analyze --no-pub`：0 issues。
- 现有 mock 集成入口：`flutter test --no-pub integration_test\app_test.dart`：2/2。
- Windows Debug smoke 构建通过。
- Windows Release 默认入口构建通过：`build\windows\x64\runner\Release\matrixflow_native.exe`。

## 未测与残余限制

- 没有用第二个 Windows 用户或另一登录会话做实测。作用域按上面的 SID 规则实现；跨会话只能转发参数，不能激活另一会话的窗口。
- 没有点击真实 Windows 通知。冷启动点击仍依赖当前缺失的 `LocalServer32`，本包没有新增该注册，避免在 COM 激活器尚未注册时由系统再拉起进程。
- 没有操作真实托盘菜单。隐藏和恢复覆盖的是托盘已经使用的 Win32 显示通道。
- 转发失败时的退出码 2 和提示框没有在成功路径上出现，因此没有单独实测。
- `Global\` 权限不足时的会话互斥量退路没有在本机出现。
- 系统强杀仍不能保证已经开始、尚未完成的那次写入。单实例只保证崩溃后的下一次启动不会和已死进程并存。
- 未做 Android 设备验证。闸门只在 Windows runner；Android 不经过这段入口。
