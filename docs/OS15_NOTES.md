# OS15 实施记录

## 基线与范围

- 基线：`cc9ce2765dc90211d58cfc487c8b9c2bfc442124`
- 分支：`os15-desktop-exit`
- worktree：`D:\Dev_project\martix-wt-os15`
- 只实施 OS15；未开始 OS16。
- 未修改 `storage.dart`、`settings_screen.dart`、`l10n.dart` 或公共交接文档。

## 实现

- 窗口关闭与托盘退出统一进入 `DesktopShellService.exitApplication()`：并发请求共享同一个进行中 Future，完成后再次请求不会重复销毁；取消或失败后允许重试。
- 关闭到托盘保持独立语义：托盘可用时仅隐藏窗口，不触发退出守卫或销毁。
- Windows host 不再在托盘菜单回调后直接 `destroy()`；host 自身缓存销毁 Future，避免重复释放。
- 集成修正：原生 `destroy()` 失败时清除缓存的 Future，下一次退出可以重新尝试释放。
- Windows runner 的 `Win32Window::Destroy()` 增加生命周期幂等保护，避免显式销毁、`WM_DESTROY` 重入和析构路径重复执行 `OnDestroy()`。
- `MatrixHome` 在真正退出前处理当前任务详情或新建任务草稿；用户选择继续编辑时取消退出，选择放弃后才进入保存协调。IME composition 场景不会被当作提交动作，取消退出保留草稿文本且不创建任务。
- 保存协调先调用现有 `Store.flush()` 并等待最新队列；失败或 8 秒超时后明确提供“重试 / 不保存并退出 / 取消退出”。重试调用现有 `Store.retrySave()`，只有成功或用户明确选择不保存时才允许最终销毁。
- 新增独立 `desktop_exit_strings.dart`，保存失败/超时退出文案覆盖英文、简体中文和日文，未触碰公共 `l10n.dart`。

## 自动化验证

固定 SDK：`D:\Dev_SDKs\Flutter_3.32.8`（Flutter 3.32.8 / Dart 3.8.1）。

- OS15 专项：`flutter test --no-pub test\os15_desktop_exit_test.dart`：12/12 通过。
- 桌面相邻专项：`flutter test --no-pub test\desktop_shell_test.dart test\os14_desktop_shell_test.dart test\os15_desktop_exit_test.dart`：24/24 通过。
- 默认全量：`flutter test --no-pub`：468/468 通过。
- 静态分析：`flutter analyze --no-pub`：0 issues。
- Windows Debug 独立 smoke 入口构建：通过，产物为 `build\windows\x64\runner\Debug\matrixflow_native.exe`。
- Windows Release 默认入口构建：通过，产物为 `build\windows\x64\runner\Release\matrixflow_native.exe`。

## Windows 真实关闭验证

新增 `tool/os15_windows_exit_smoke.dart`。该入口不创建 `Store`、不读取用户任务数据，使用独立窗口完成桌面初始化，在退出守卫完成并写入 `COORDINATOR completed` 证据后调用真实 host 销毁。

本轮三次尝试启动已构建的独立 Debug 实例，均在执行前被 IDE 的外部 GUI 进程授权提示超时取消；因此没有把“进程真实退出”登记为通过。Debug/Release 编译均已通过，但真实关闭仍需在可批准 GUI 启动的会话执行：

集成补测（2026-09-25）：在 main 的隔离 Debug 实例中完成真实退出，报告依次为 `START`、`EXIT requested`、`COORDINATOR started`、`COORDINATOR completed`，随后 `flutter run` 输出 `Lost connection to device.` 并以 0 退出。本段保留独立分支当时未测的历史记录。

```powershell
cd D:\Dev_project\martix-wt-os15\matrixflow-native
$env:MATRIXFLOW_OS15_SMOKE_RESULT="$PWD\build\os15_exit_smoke_result.txt"
D:\Dev_SDKs\Flutter_3.32.8\bin\flutter.bat run -d windows --no-pub -t tool\os15_windows_exit_smoke.dart
Get-Content $env:MATRIXFLOW_OS15_SMOKE_RESULT
```

预期进程自行结束，报告至少依次包含 `START`、`EXIT requested`、`COORDINATOR started`、`COORDINATOR completed`。不要在用户正在使用的 MatrixFlow 实例上执行退出测试。

## 边界与残余限制

- 系统强杀、断电和操作系统直接终止进程无法保证草稿或尚未提交的写入完成。
- `Store.flush()` 超时不会取消底层 SharedPreferences 写入；取消退出后该写入可继续完成，重试仍通过 Store 自身队列串行化。
- 本包未做 Android 设备验证；Android 不启用桌面 host，默认全量测试覆盖了共享 UI 回归。
