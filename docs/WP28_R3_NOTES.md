# WP28-R3：独立 Windows 原生验收 CI

基线：`459f9a28cefdcac9196825b2d4ac70250dbf3b8d`。独立分支 `codex/wp28-r3`，
工作树 `D:/Dev_project/martix-wp28-r3`。固定 Flutter 3.32.8 / Dart 3.8.1，
`pubspec.lock` 未变；独立 `PUB_CACHE=D:/Dev_project/martix-wp28-r3-cache`。
没有修改主检出、`pr.yml`/`release.yml`、产品入口、Store、签名、版本或模型锁。
本包不推送。云端实际跑矩阵留给集成。

## 实现范围

- 独立工作流 `.github/workflows/wp28-native-validation.yml`：`pull_request` 与
  `workflow_dispatch`，`windows-2022`，`timeout-minutes: 180`，并发取消旧跑。
  权限仅 `contents: read` + `actions: write`（上传证据）。无密钥、无签名、无发布。
- 分配 `RUNNER_TEMP` 下唯一 GUID 证据根；`if: always()` 上传成功报告与失败证据，
  `if-no-files-found: error`。缺桌面写成失败证据，不是 skip-success。
- 编排脚本 `scripts/wp28_r3_windows_ci.ps1` 默认无 `-Run` 不启动应用（退出 2）。
  `-Run` 后：新鲜证据根、源码指纹、钉死 SDK、`pub get --enforce-lockfile`、
  桌面探测、编译门负例、Debug/Release 诊断构建 + 矩阵 + 运行时负例，再汇编报告。
- 桌面探测在独立 MTA 线程上 `CreateDesktopW`/`OpenInputDesktop`/`SetThreadDesktop`，
  不切换输入桌面、不抢前台。Session 0 或无交互桌面记 `usable=false` 并失败。
- 汇编器拒绝复用旧成功报告；超时、强杀、清理失败、未知门禁状态、跳过、
  `normalCandidate!=false` 或 commit/源码/EXE 哈希不一致一律失败。
- R2 脚本仅做 CI 移植：可传入 Flutter、超时、证据路径；诊断相对路径不依赖
  `Path.GetRelativePath`；门禁在 `$ErrorActionPreference=Stop` 下仍捕获 Flutter 日志；
  harness 用 UTF-8 读 JSON（避免中文 Windows PowerShell 5.1 按 GBK 读坏合成库）。

## 本地验收

固定 SDK `D:/Dev_SDKs/Flutter_3.32.8`。脚本无 `-Run` 退出 2。工作流静态测试
14 项、R2 审计 6 项通过。`flutter analyze --no-pub` 无问题。未跑默认全量：
未改产品行为。

完整矩阵证据根
`D:/Dev_project/martix-wp28-r3/build/wp28-r3/2529b808-e0fe-4311-b432-c06fe6aa1c1d`。
`ci-report.json`：`passed=true`，`skip=false`，`normalCandidate=false`，
`failures=[]`，commit `459f9a28cefdcac9196825b2d4ac70250dbf3b8d`。
桌面探测 `usable=true`，`isolated=true`，session 1，输入桌面 Default。
编译门三项均 exit 1（native-only / dart-only / combined），脚本 exit 0。
Debug：20 场景、73 进程，EXE `83A9CAE324D110C572BA444EAAE7ED7AAF0EAE0728082C48477692B24B6531EF`。
Release：20 场景、73 进程，EXE `FE461D697B36AD2D63B5FC12B00FD95432A749A02A29698782D2D160E2FB05D3`。
Debug/Release 运行时十项负例均 exit 2、`timedOut=false`、`cleanup=not-needed`。
编排退出码 0。证据在忽略的 `build/` 下，不提交。

## 云端与杀毒

托管 runner 若不能 `CreateDesktop`/`OpenInputDesktop`，工作流必须失败并上传证据，
需要受控交互会话，不能改成无条件 skip。部分杀毒会把探测脚本的内存 Win32 桌面
调用当成注入；那是隔离探测，不是发布载荷。
