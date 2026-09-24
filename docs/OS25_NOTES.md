# OS25 — 无密钥 PR 检查与集成测试

日期：2026-09-25。只实施 OS25。未开始 OS26。未改产品 UI、Store、桌面或提醒业务代码，也未改 AGENTS、HANDOFF、ARCHITECTURE、CHANGELOG 或开源计划。

## 基线

- 独立 worktree：`D:\Dev_project\martix-wt-os25`
- 分支：`os25-ci`
- 起点：`cc9ce2765dc90211d58cfc487c8b9c2bfc442124`（`docs(plan): 划清下一波并行文件归属`）
- 工具链：OS24 固定的 Flutter 3.32.8 stable / Dart 3.8.1，framework `edada7c56edf4a183c1735310e123c7f923584f1`，本机 `D:\Dev_SDKs\Flutter_3.32.8`
- 本机 `flutter --version` 读到 Flutter 3.32.8、revision `edada7c56e`、Dart 3.8.1、DevTools 2.45.1

## 改动

- `.github/workflows/pr.yml`：`pull_request` 和所有分支 `push` 都跑检查，不靠 tag。权限只有 `contents: read`。四个 job 都安装 Flutter 3.32.8 stable，并用 `toolchain.json` 核对版本、Dart 和 framework revision。
  - `analyze-and-test`：`flutter pub get`、`flutter analyze --no-pub`、`flutter test --no-pub`。测试步骤没有 `continue-on-error`。
  - `android-debug`：Temurin 17，`flutter build apk --debug`，`REQUIRE_RELEASE_SIGNING=false`。不构建 release，不读取发布密钥。
  - `windows-debug`：`flutter test --no-pub integration_test/app_test.dart`，然后 `flutter build windows --debug`。
  - `platform-smoke`：只有 `workflow_dispatch` 且 `run_platform_smoke=true` 才运行。普通 PR 上这个 job 是跳过，不是通过。分析 job 会写明真实通知/托盘 smoke 不在 PR 检查里。
- `.github/workflows/release.yml`：正式 Android release 构建设置 `REQUIRE_RELEASE_SIGNING=true`。原有的密钥缺失即退出仍然保留。
- `matrixflow-native/android/app/build.gradle.kts`：配置阶段不再因为 `CI=true` 抛错。`verifyFormalReleaseSigning` 只挂在 `preReleaseBuild`、`assembleRelease` 和 `bundleRelease` 上，并且只有 `REQUIRE_RELEASE_SIGNING=true` 且 keystore 不存在时才失败。无密钥的 debug 构建继续使用 debug 签名。
- `matrixflow-native/integration_test/app_test.dart`：mock 集成。调用生产 `main()`，关闭真实 Windows shell，使用 `NoopReminderService` 和内存凭据。`SharedPreferences.setMockInitialValues` 隔离用户 profile。HTTP mock 绑定 `127.0.0.1:0`。`GET /models` 返回模型列表，`POST /chat/completions` 返回分类任务，其他路由返回 404。已完成引导时走 `add-task-btn` / `task-input` / `submit-tasks`，不再找已删除的 FloatingActionButton。缺少引导标记时，首屏可点击的是 `onboarding-skip-btn`，跳过之后才可点击新建。
- `matrixflow-native/tool/os25_platform_smoke.dart`：真实 Windows 通知和托盘 smoke。不构造 Store，不读写任务 profile。显示一条合成通知后取消，初始化托盘后销毁。非 Windows 进程写 `NOT-RUN` 并以退出码 2 结束。
- `matrixflow-native/test/os25_ci_test.dart`：把上述 workflow、签名门槛和 mock/真实边界锁进默认测试。

仓库没有 remote。GitHub Actions 没有实际跑过，不能把 workflow 文件写成已通过的远端检查。

## 本机证据

命令都在 `matrixflow-native/`，Flutter 为 `D:\Dev_SDKs\Flutter_3.32.8\bin\flutter.bat`。

| 检查 | 结果 |
|---|---|
| `flutter test --no-pub test/os25_ci_test.dart` | 3/3 |
| `flutter test --no-pub integration_test/app_test.dart` | 2/2。Flutter 构建并启动了 Windows debug 应用，不是删除测试后的空通过 |
| `flutter test --no-pub` | 459/459。其中含 OS25 契约 3 项。既有 widget 测试仍有两条 tap 未命中警告，测试本身通过 |
| `flutter analyze --no-pub` | No issues found |
| 故意失败探针 | 临时测试 `expect(true, isFalse)` 的进程退出码是 1，文件已删除，不在本次提交里 |
| `CI=true` 且 `REQUIRE_RELEASE_SIGNING=true` 时 `:app:verifyFormalReleaseSigning` | 失败，退出码 1。信息：`Formal release signing credentials are required. Refusing to publish a debug-signed APK.` |
| `CI=true` 且未设置 `REQUIRE_RELEASE_SIGNING` | 同一任务成功，退出码 0 |
| `CI=true` 且 `REQUIRE_RELEASE_SIGNING=false` | 同一任务成功，退出码 0 |
| `CI=true` 且 `REQUIRE_RELEASE_SIGNING=true` 时 `:app:tasks` | 配置阶段成功，退出码 0。`CI=true` 本身不再挡住 Gradle 配置 |
| `CI=true`、`REQUIRE_RELEASE_SIGNING=false`、无 keystore 时 `flutter build apk --debug` | 成功。产物 `build/app/outputs/flutter-apk/app-debug.apk`，207,871,170 字节。这是 debug 包，不是正式签名产物 |
| `flutter build windows --debug` | 成功。产物 `build/windows/x64/runner/Debug/matrixflow_native.exe` |
| `flutter run -d windows -t tool/os25_platform_smoke.dart --no-pub` | 退出码 0。报告：`PASS notification=shown tray=success profile=untouched` |
| `adb devices` | 只有表头，没有 Android 设备 |

Android debug 构建中，Kotlin daemon 仍对跨盘增量缓存报错（pub cache 在 `C:`，工程在 `D:`），随后回退并完成 `assembleDebug`。这和既有合并记录里的现象同类，不是签名失败。

真实 smoke 在本机桌面显示了一条标题为 `OS25 smoke` 的通知，随后取消；托盘图标创建后销毁。它没有打开任务库。

## 没有覆盖的场景

- GitHub 托管 runner 没有执行。Windows job 里的 mock 集成测试依赖可启动的桌面会话；本机 Windows 已通过，托管 runner 尚未证实。
- 没有 Android 设备，因此没有 Android 上的 mock 集成或真实通知 smoke。
- 没有正式 keystore，没有打正式 release APK。缺签名现在只应挡住设置了 `REQUIRE_RELEASE_SIGNING=true` 的 release 任务。
- 公共交接文档仍写着 OS25 未开始。集成时再更新。
