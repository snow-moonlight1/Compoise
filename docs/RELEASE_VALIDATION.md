# 发行验证清单

WP28 的发行准备材料：门禁命令、平台交付事实、安装与升级验证步骤、仍缺少的凭据与证据。当前状态是**不具备正式发行条件**，原因见[剩余缺项](#剩余缺项)。

正式安装包、原位升级验证和 GitHub Release 必须使用同一个最终候选提交重新生成，包含已集成的日程 v3 与 Windows 升级适配。版本号在发行时统一确定；本文所有 `vX.Y.Z+N` 都是占位，不代表 `1.0.0+1` 可以打 tag。

## 当前候选规则（2026-10-03，D2/D3、I6、R1 集成）

WP15-D2/D3、WP17-I6 与 WP28-R1 已接收独立提交。集成时保留两套 Android 验收身份，并禁止同时启用；发行脚本增加 D3 诊断环境拦截，明确构建 `lib/main.dart`。默认 CI 增加官方 OCR bundle 与候选校验的 Python 回归。

| 集成树检查 | 实际结果 |
|---|---|
| 固定 SDK 分析与默认全量 | analyze exit 0；短路径修复后 1404 项通过 / 10 条件跳过，test exit 0 |
| 候选校验与 OCR Python 回归 | 24 项 / 21 项通过，均 exit 0；含五种诊断环境的实际预检拒绝 |
| 两套 Android 诊断身份同时启用 | Gradle 按预期 exit 1，正常身份不变 |
| 正常 Android Debug 主入口 | build exit 0，实际 APK 包名 `com.matrixflow.app`；未安装 |
| D3 Windows 私有桌面矩阵 | 6 业务场景通过，build/driver/native/script 均 exit 0，无进程/临时库残留，宿主时区未改 |
| Windows 升级/路径专项回归 | 73 项通过，exit 0；真实 8.3 短路径迁移与真实 junction 拒绝均通过 |

首轮全量暴露 OS25 旧断言仍要求 CI 直接执行 Flutter APK 构建；已按 R1 的统一发行脚本接线更新，未放宽签名门，随后全量通过。D3 原生证据记录 commit `8a9eea9bcb4287d144065c70addf7388de430722` 与 dirty=true（集成脚本/文档修改尚未提交），不是声称运行了后续提交的二进制；日志在忽略目录 `build/wave-20261003`，原生报告在 `build/wp15-d3/windows-result.json`。最后正常 Windows 候选从最终集成提交重新构建，云端结果以该提交的 Actions 记录为准。

首个手动云端候选在 Windows 全量测试中发现 41 项升级失败：Runner 临时目录使用 `RUNNER~1`，解析后的长名称被旧路径检查误判为重定向。本地真实 8.3 名称复现同一失败；现用 [Win32 长名称展开](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-getlongpathnamew)比较同目录名称，逐级类型与重定向检查继续执行，真实 junction 仍拒绝。默认 Windows CI 已增加这些专项回归。未删除失败用例或更改 Runner 临时目录规避问题。

第二次候选全量只有 RF08 的一项时间断言失败（1403 通过 / 1 失败 / 10 跳过）：测试把同一毫秒的两个失败时间当作同一代重试，实际次数和预算已正确重置。现从带明确旧时间的持久化耗尽记录开始，继续断言无关编辑保留原预算/时间、用户重试清零预算并重置年龄、变更触发时间替换原记录；不靠睡眠等待时间戳不同，提醒产品代码未修改。

本地与 CI 共用 `scripts/release_candidate.py`，以 `proof → seal → verify` 检查二进制、完整 commit、工具链、源码差异指纹、身份/签名和 ZIP 每个文件。`RELEASE_MANIFEST.txt` 现为 **JSON schema 1**，metadata 从同一记录生成；旧轮的文本字段不适用于新候选。Windows 候选可记录有差异的源码，正式双平台 `assemble` 必须没有源码差异。

手动运行 `.github/workflows/release.yml` 只做预检及 Windows 候选构建/上传，不使用生产签名凭据或创建 Release。`v*` tag 推送才会启用 Android、Linux 与草稿发布阶段。版本仍为 `1.0.0+1`，本轮没有批准该版本正式发行。

I6 的官方模型 Android 真实 SAF 全流程已通过，Linux 的通过路径注入了文件选择；真实 GTK 多选、arm64、10 图、低端设备及独立进程重开仍缺证据。默认候选不含 OCR。细节分别见 [D3](WP15_D3_NOTES.md)、[I6](WP17_I6_NOTES.md)、[R1](WP28_R1_NOTES.md)。

## 前轮集成检查（2026-10-03，I5/U2）

WP17-I5 已应用独立提交；WP28-U2 由集成端接收未提交实现、补齐恢复页修复、Release 验收和交接记录。WP15-D2 的进行中改动未加入这次集成。

| 检查 | 本地结果 |
|---|---|
| `flutter analyze --no-pub` | 无问题，exit 0 |
| 默认全量 `flutter test --no-pub` | 1396 项通过、7 项按条件跳过，exit 0 |
| U2 凭据/确认/损坏恢复专属测试 | 20 项通过，exit 0 |
| 官方模型 + Windows 外部 OCR 库定向测试 | 16 项通过，exit 0；不作为应用 bundle/Android 全流程证据 |
| OCR 准备与转换回归 | Windows 16 项通过，exit 0 |
| U2 隔离 Release 原生矩阵 | 12 场景、52 进程全部 exit 0；无超时或残留，harness exit 0 |
| 正常入口 Windows Release | 构建 exit 0；复核 Dart/native 隔离门均已关闭 |

原 Agent 的 U2 Debug 矩阵为 12 场景、52 进程，报告已经复核；Release 是集成端在当前源码上新运行的证据。I5 关闭官方模型转换技术阻塞，默认包仍不包含 OCR；正式包装和完整设备导入仍待完成。

## 前轮集成检查（2026-10-01）

WP15-D1、WP17-I4 与 WP28-U1 的独立提交已集成，公共导航与范围说明同步更新。

| 检查 | 本地结果 |
|---|---|
| `flutter analyze --no-pub` | 无问题，exit 0 |
| 默认全量 `flutter test --no-pub` | 1376 项通过、7 项按条件跳过，exit 0；设备/外部模型测试跳过不算设备验收 |
| Windows Release 外部 OCR 库 + I1/I3a/I4 测试 | 16 项通过，exit 0；仍使用仅供验证的权重 |
| OCR 准备脚本回归 | 7 项通过，exit 0；只用临时合成转换产物与已校验本地字典/头文件 |

CI 的四项默认门禁仍检查分析/默认测试、Android APK、Linux bundle 与 Windows 构建；本轮增加 OCR 准备只读回归。默认 CI 不加载 OCR 模型，不替代设备识别、通知、签名或发行验收。各包的原始设备证据与未验收项保留在对应记录中。

## 门禁命令

`scripts/build_release.ps1` 在 Windows PowerShell 和 Linux/macOS 的 `pwsh` 下都可运行预检：

```powershell
# 只做版本、tag、签名前置与产物计划检查，不构建、不写文件
pwsh -File scripts/build_release.ps1 -Platform All -ExpectedTag vX.Y.Z+N -ValidateOnly
```

```powershell
# 本机完整打 Windows 便携包：构建 + 身份校验 + ZIP 清单 + SHA256SUMS + RELEASE_MANIFEST
powershell -File scripts/build_release.ps1 -Platform Windows -ExpectedTag vX.Y.Z+N -FlutterSdk <SDK 目录>
```

```powershell
# Android 正式包：必须先有发布签名材料（见 android/key.properties.example）
powershell -File scripts/build_release.ps1 -Platform Android -ExpectedTag vX.Y.Z+N
```

脚本自身的规则，验证时按这些现象判定，不要手工绕过：

| 检查 | 失败现象 |
|---|---|
| `pubspec.yaml` 必须是 `X.Y.Z+N`，且与 `-ExpectedTag` 一致 | `Refusing to stage a release whose tag and version disagree.` |
| Android 无发布签名材料时拒绝构建 | `Refusing to build a debug-signed release APK.` |
| 暂存目录里出现非本次产物，或证明/摘要不匹配 | `Candidate file set differs ...` 或对应校验错误 |
| 工具链与 `toolchain.json` 不一致 | `The active Flutter SDK does not match or cannot be read ...`；`-AllowUnpinnedSdk` 只允许预检计划，不能打包候选 |
| 可执行文件版本、身份字段、ZIP 清单不符 | 抛出对应 `The built executable ...` / `The staged ZIP does not contain ...` |
| 环境启用 OCR、U2 或 D3 诊断构建 | `Default release rejects active opt-in gate: ...`，预检与打包均拒绝 |

产物校验和（Windows 上可用 `Get-FileHash`，其余平台用 `sha256sum`）：

```sh
sha256sum -c --strict SHA256SUMS.txt
```

CI 侧 `.github/workflows/release.yml` 在推送 `v*` tag 时按 `preflight → build-android / build-windows / build-linux → publish-release` 执行，只产出**草稿** Release，需人工复核后发布。手动运行只走预检和 Windows 候选。权限默认 `contents: read`，只有 publish job 申请 `contents: write`。

## 平台交付事实

| 平台 | 交付物 | 签名事实 | 验证状态 |
|---|---|---|---|
| Android | `compoise-vX.Y.Z+N-android.apk` | 需用仓库 secret 中的发布 keystore 签名；CI 另要求 `ANDROID_RELEASE_CERT_SHA256` 给出期望证书指纹，调试签名或指纹不符即失败 | **未验证**：尚无发布 keystore，也没有真机安装证据 |
| Windows | `compoise-vX.Y.Z+N-windows-portable.zip`（便携目录，非安装器） | **未做 Authenticode 签名**，SmartScreen 可能告警；脚本与 CI 都按“未签名”如实记录，签名状态异常（HashMismatch/NotTrusted）即拒绝暂存 | 打包门禁本机实测通过；U2 隔离 Debug/Release 升级退出已验证，正式版本原位升级仍待验证 |
| Linux | 无交付物 | 不适用 | 预览：CI 用固定工具链编译并检查 `build/linux/x64/release/bundle/`（可执行文件名仍是 `matrixflow_native`），不启动界面、不打包、不签名 |

发布说明中这三条必须原样表达；`RELEASE_METADATA.txt` 与 `RELEASE_MANIFEST.txt` 会写入 tag、完整 commit、工具链、Android 证书 DN 与 SHA-256、Windows 签名状态和 `license=GPL-3.0-only`。项目许可为 GPL-3.0-only，第三方素材见 `assets/licenses/THIRD_PARTY_NOTICES.txt`。

## Windows 应用数据目录契约

Windows 的任务库位置不是安装目录，而是 exe 版本信息派生出来的应用目录：`shared_preferences` 经 `path_provider_windows` 取 `%APPDATA%\<CompanyName>\<ProductName>`，`shared_preferences.json` 和 `flutter_secure_storage.dat` 都落在里面。因此 **`CompanyName` + `ProductName` 就是数据目录的身份**，改动等于换库。

- 2026-09-16 起的构建：`%APPDATA%\com.matrixflow\MatrixFlow AI`。
- `d9e3b56`（2026-09-27，开源准备）把两个字段改为 `Compoise` / `Compoise`，此后构建读取 `%APPDATA%\Compoise\Compoise`。

WP28-U1 已集成启动升级适配：在提醒和 Store 打开前检查两处目录，当前目录已有资料时优先使用当前库；只在目标不存在时校验并复制旧首选项，使用不覆盖目标的原子提交。旧目录始终只读，损坏或失败提供恢复与重试，不初始化空库掩盖错误。加密凭据不跨目录复制，提示重新配置。`test/os26_release_test.dart` 仍固定当前身份。

[U2 记录](WP28_U2_NOTES.md)已收口提示生命周期与原生退出：已读说明不再反复阻断启动，配置状态只有安全写入/读回验证后清除；引擎在 COM 释放前销毁。隔离 Debug 与 Release 的升级、退出、重开及并发启动矩阵已有证据。真实发行安装包的原位升级验收通过前，“原位升级保留任务”仍不能勾选。

## 验证步骤

统一要求：只使用合成任务数据；每台设备/每个环境记录应用版本（设置页或标题）、构建 commit（`RELEASE_METADATA.txt` 的 `commit=`）、平台与系统版本；失败保留可复现操作序列，不提交真实备份或密钥。

### 1. 干净环境启动

| 平台 | 步骤 | 期望 |
|---|---|---|
| Android | 全新设备或清除数据后安装 APK，首启 | 引导页出现、默认板与空矩阵正常，三语切换可用；无网络权限也不影响普通任务；日志中无未处理异常 |
| Windows | 解压 ZIP 到新目录（或新虚拟机），双击 `compoise.exe` | 首次运行创建 `%APPDATA%\Compoise\Compoise`；单实例锁生效（二次启动只唤起已有窗口）；关闭窗口按桌面设置退出或进托盘 |
| Linux 预览 | 解压/复制 CI 构建的 bundle，在图形会话中运行 `bundle/matrixflow_native` | 能启动并完成新建、勾选、切换任务板；密钥保存需已解锁的 Secret Service 默认密钥环，缺失时提示可理解且不崩溃；无系统通知、托盘、全局快捷键属已知限制 |

### 2. 安装

- Android：`adb install -r <apk>` 前后 `adb shell dumpsys package com.matrixflow.app | grep -E 'versionName|versionCode|signatures'`，确认 versionCode 与 `pubspec.yaml` 的 build 号一致、签名为发布证书；`adb shell pm list packages -f com.matrixflow.app` 确认安装身份仍是 `com.matrixflow.app`（包名变更会另起数据沙箱，见 [Android 应用身份](ANDROID_PACKAGE_MIGRATION.md)）。
- Windows：校验 `SHA256SUMS.txt` 后解压到不含中文与只读限制的路径，启动、退出、再启动各一次。
- 首启后 `git`-无关的界面截图仅用合成任务，正式发布截图须来自最终合并提交。

### 3. 原位升级保留任务

1. 在**旧版本**创建可辨识的合成数据：多任务板、父子任务、截止日期与提醒、长纯文本备注、已完成项、AI 配置（密钥留在本机）。
2. 旧版本设置页导出 JSON 备份（默认不含密钥），另存为升级前对照。
3. 安装新版本：Android 用 `adb install -r` 同一签名 APK；Windows 用新 ZIP 解压**覆盖**同一安装目录；Linux 覆盖 bundle 目录。
4. 启动后逐项核对：板与任务数量、父子结构与顺序、日期/提醒时间、备注文本、完成状态、活动板与引导状态；再修改一条任务并重启，确认写入生效。
5. 证据：升级前后任务数量与关键字段对照表；Windows 记录源/目标目录，确认当前库优先、旧库原文保留及新目录重开可用（见上文契约）。

Android 的“同签名”是硬前提：换发布证书即视为不同应用，原位升级会被拒绝。

### 4. 备份往返

1. 候选版本导出 JSON（默认 `ExportData` v3），记录文件数、卷号与日程条数。
2. 清除数据（Android 清除应用数据；Windows/Linux 移走应用目录）后在版本 A 导入：第 1 卷选“覆盖”，其余卷按文件名顺序“合并”，每卷选同一目标板。
3. 与导出前对照：板、任务、子项、纯文本备注、日期与提醒、日程绝对时刻及 IANA 时区、设置与 AI 配置（除密钥）逐字段一致。契约与上限见 [备份格式](BACKUP_FORMAT.md)。
4. 跨版本：新版本继续导入 v1/v2；v3 文件不要求旧版本读取。显式降级导出 v1/v2 必须提示日程丢失，v1 的其他有损字段按格式契约核对。回退旧可执行文件前先保留完整 v3 备份，不能声称旧版重存后仍保留日程。
5. 升级到新版本后，再用步骤 2 的备份在**新版本**导入一次，验证升级路径与导入路径不冲突。
6. 只有显式勾选“包含密钥”的备份才会写出明文密钥；这类文件不得进仓库、issue 或聊天工具。

## 剩余缺项

以下项目前**没有**，正式发行不能继续；补齐方式不包含放宽门禁：

- **凭据**：Android 发布 keystore 及其 `storePassword`/`keyPassword`/`keyAlias`，以及 CI 用的 `ANDROID_KEYSTORE_BASE64` 与 `ANDROID_RELEASE_CERT_SHA256`（发布证书 SHA-256 指纹）。缺任一项，`build-android` 与本地 `-Platform Android` 都会拒绝。
- **凭据**：Windows Authenticode 证书（或明确接受长期未签名发行，并在发布说明与商店文案中持续披露 SmartScreen 风险）。
- **设备证据**：Android 真机的安装、同签名原位升级与提醒（minSdk 23 与当前 target 各一台）；Windows 从一个已发布构建到候选构建的原位升级（含上文数据目录判定）；Linux 桌面会话的启动与核心流程手动检查。CI 只覆盖编译与 mock 集成测试。
- **渠道资料**：GitHub Release 的正式版本策略与 tag 约定、发行渠道选择（Direct APK / Google Play / F-Droid 等）及其账号、签名上传地址、隐私政策与支持的 URL、商店素材与截图。
- **产品事实**：版本号、功能描述与截图以最终候选提交为准；默认构建不含 OCR，不能把实验识别写成正式支持。[商店介绍草稿](STORE_LISTING.md)需按最终界面复核。
- **流程**：`.github/workflows/release.yml` 的 publish job 只在 tag 推送时运行。手动 Windows 候选通过也不等于签名/双平台装配/发布阶段通过；首个正式 tag 仍须按草稿流程演练后复核。

## 验证记录（2026-09-28，WP28 准备轮，基线 `origin/main` `5b3b39e`）

环境：Windows 主机 PowerShell 5.1；WSL Ubuntu 24.04 + 便携 PowerShell 7.5.11 + Flutter 3.32.8（revision `edada7c56e`、engine `ef0cd00091`、Dart 3.8.1，与 `toolchain.json` 一致）。

| 项 | 结果 |
|---|---|
| Linux 预检 `-Platform Windows/All -ValidateOnly` | **修复前必失败**：`Refusing to stage outside the output directory`（暂存目录包含性检查写死 `\`），意味着 `release.yml` 的 preflight job 在任何 tag 上都无法通过；改用父目录比较后两侧均通过，退出码 0 |
| 未安装 Flutter 时的工具链声明 | 修复前打印 `matches toolchain.json`（假合规），现如实输出 `not probed (Flutter SDK not found)` |
| `-ExpectedTag v9.9.9+9`、`-OutputDir /` | 均按预期拒绝 |
| keystore 布局解析（`android/key.properties` + `android/app/release.jks`，即 CI 与模板文档采用的布局） | 修复前误报“找不到 keystore”从而拒绝合法配置，现按 Gradle 顺序解析，Windows 与 Linux 两侧一致；keystore 缺失时仍如实报 MISSING |
| `-FlutterSdk <Linux SDK>` | 修复前挑到 `bin/flutter.bat` 而无法执行，现按宿主选择启动器并成功探测固定版本 |
| Windows 真实打包（`-Platform Windows`，构建 + 身份校验 + ZIP + 校验和 + manifest） | 通过：全新构建 255 s、增量重跑约 2 min；ZIP 13,405,301 字节、19 个条目，`SHA256SUMS.txt` 与 `RELEASE_MANIFEST.txt` 正常写出；manifest 记录 `gitCommit=5b3b39e6…`、`toolchainPinState=matches`、`windowsCodeSigning=unsigned (Authenticode is not configured)`、`license=GPL-3.0-only`、`appDataDir=…\Compoise\Compoise`、`authenticode=NotSigned` |
| 身份字段断言 | 修复前脚本仍要求 `LegalCopyright` 含 `com.matrixflow`，而 `d9e3b56` 之后实际值是 `Copyright (C) 2026 Compoise contributors.` ⇒ 真实打包必然抛错。现断言当前身份，并新增 `CompanyName` 检查与应用目录记录 |
| 脏树标记的可解释性 | manifest 的 `gitWorkingTreeDirty=True` 现在附带 `gitWorkingTreePaths=…`。注意 `flutter pub get` 会重新生成未被跟踪的 `linux/flutter/generated_*` 三个文件，因此**只做过 pub get 的干净检出也会显示为脏**；`windows/flutter/generated_*` 是已跟踪的。建议集成时决定提交或忽略这三个 Linux 文件，与仓库既有的 Windows/Android 约定保持一致 |
| 数据目录漂移 | 读取自 2026-09-27 构建的 `compoise.exe`：`CompanyName=Compoise`、`ProductName=Compoise` → `%APPDATA%\Compoise\Compoise`（该目录不存在）；旧库仍在 `%APPDATA%\com.matrixflow\MatrixFlow AI\shared_preferences.json`（最后写入 2026-09-25） |
| `release.yml` 全部 job 步骤 | YAML 解析通过；23 个 bash 块 `bash -n` 通过；4 个 PowerShell 块解析通过（表达式先替换）；publish job 的各步骤在 Linux 沙箱按伪产物实跑：产物装配、发布说明、metadata、产物集合门禁、`sha256sum -c --strict` 全部通过 |
| 门禁反例 | 多余文件、metadata 缺完整 commit、缺一侧平台产物、缺 Android 签名证明 → 全部拒绝；发布后再篡改产物 → `sha256sum -c` 报失败 |
| 期间发现并修正的自引入缺陷 | 产物计数用 `grep -v` 在“全部合规”时退出码 1，配合 `pipefail` 会让成功路径中止；已按预期路径修正并纳入反例复测 |
| 签名门禁未被放宽 | `-Platform Android` 且无 keystore 时退出码 1，抛 `Formal release signing credentials are required. … Refusing to build a debug-signed release APK.`，在暂存与构建之前即中止；工具链缺失时同样早退 |
| 可复现性 | 同一未修改树连续两次打包得到相同的 `compoise-v1.0.0+1-windows-portable.zip` SHA-256（`338a2c106856e223913d89aec10e5ba5452c3c02a9ad90d7f4ab52cf73d4df19`，13,405,301 字节）；正式版本需在合并提交上重新生成 |
| 仓库门禁 | `flutter analyze --no-pub` 无问题；`flutter test --no-pub` 全绿（846 项；`test/os26_release_test.dart` 12 项，其中本包新增 6 项） |
| 未执行 | Android 真机与签名构建（无凭据）、GitHub 上的真实 tag 演练、三平台手动安装/升级/备份往返（需候选提交与设备） |
