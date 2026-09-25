# OS27 验证记录：平台运行证据、文档命令核对与公开状态审计

日期：2026-09-25。子批次：**OS27-C（平台与公开状态证据）**。
本包不修改产品代码，不修改 Agent A/B 独占文件（文档体系、三语文案及引导），不修改公共 `AGENTS.md`、`docs/HANDOFF.md`、`docs/CHANGELOG.md` 与实施计划。
仅记录隔离环境下的真实验证数据、文档构建/测试命令核查、公开声明审计与未测限制，供集成人统一收口。

---

## 1. 接手与验证环境

- **基线提交**：`1625c1767b1893847ff4650218aba0e41a2886d4`（`fix(integration): 收口 OS21 OS22 合并回归与下一波交接`）。
- **独立工作树**：`D:\Dev_project\martix-wt-os27-validation`。
- **分支**：`os27-validation`，从上述基线检出。接手时主工作区干净；未执行 reset、amend 或 push，无远端。
- **固定 SDK**：Flutter **3.32.8** stable / Dart **3.8.1**（framework `edada7c56edf4a183c1735310e123c7f923584f1`，engine `ef0cd000916d64fa0c5d09cc809fa7ad244a5767`），本机路径 `D:\Dev_SDKs\Flutter_3.32.8`，与 `matrixflow-native/toolchain.json` 一致。回退目录 `D:\Dev_SDKs\Flutter_SDK` 未改动。
- **宿主环境**：
  - 操作系统：Windows 11 企业版 10.0 Build 26200。
  - 处理器：AMD Ryzen 7 8845H with Radeon 780M Graphics（8 核 16 线程）。
  - 内存：27.81 GB。
  - 显示/刷新率：Flutter 视图报告 143.99 Hz（每帧预算 6945 µs），devicePixelRatio 2.0，逻辑窗口尺寸 1267×684.5（物理像素 2534×1369）。
  - Android 工具链：Android SDK 位于 `D:\Dev_SDKs\Android_studio_SDK`（platform android-36，build-tools 36.0.0，NDK 28.0.12433566），JDK 21 位于 `D:\Dev_SDKs\jdk-21.0.12.1+1`。

---

## 2. 用户数据与安全隔离保护证据

本包全流程严格使用合成数据、内存 mock 与临时隔离目录，绝不读取、修改或覆盖用户的真实任务库、API 凭据与备份文件：

1. **用户任务库文件**：
   - 目标路径：`%APPDATA%\com.matrixflow\MatrixFlow AI\shared_preferences.json`。
   - 验证前 SHA256：`31CDA939E8C0EFFCDCE5C7B8B51A206B3B5AF69F5071306F09090875C63B10C8`，修改时间 `2026-09-19 23:02:43`。
   - 所有集成测试、定向回归、烟雾脚本及性能评测运行后再次核对 SHA256：
     `31CDA939E8C0EFFCDCE5C7B8B51A206B3B5AF69F5071306F09090875C63B10C8`，修改时间与哈希完全未变，**百分之百保持原样（profile untouched）**。
2. **凭据安全**：
   - 凭据存储测试仅使用合成 sentinel 探针键（如 `matrixflow-os09-probe-*`），执行后立即删除。
   - 无真实 API Key 传入，无泄露到日志或文档中。
3. **正式发布与签名隔离**：
   - 未运行正式发布发布流程，未生成伪造密钥，未修改签名凭据。

---

## 3. Windows 运行与核心路径实测

### 3.1 编辑路径（Editing）

- **草稿与输入保护（OS21）**：
  - 运行 `flutter test --no-pub test/os21_page_coordination_test.dart`（11/11 通过）。
  - 验证了 `TaskEditDraft` 的脏值跟踪、只写回真正变动的字段、以及子项编辑的增量合并。
  - 验证了 IME 组字保护（`hasPendingImeComposition`）：在中文输入法组字期间，无论是点击保存按钮还是按 `Ctrl+Enter`，均不会将半截输入提交入库；组字结束后的保存立即生效。
  - 验证了子项编辑对话框（`SubtaskEditDialog`）在反复打开/关闭 3 轮后，相关的 `TextEditingController` 得到妥善 `dispose()`，无内存泄漏。
- **页面详情会话统一性**：
  - 主界面、搜索页、已完成页在并列侧栏断点统一为 924 逻辑像素（`sideDetailWidth = 350`），窗口在 1400 与 900 两档下的展开/整页表现一致。
  - 侧栏离开/切换时的草稿确认对话框逻辑一致。
- **备注与富文本编辑（WP13-A-N）**：
  - 包含在全量 `test/widget_regression_test.dart` 中，父任务与子项备注的输入、持久化、搜索高亮与放弃保护均通过。

### 3.2 设置路径（Settings）

- **AI 模型发现与会话协调（OS10/OS11）**：
  - 运行 `test/os10_model_discovery_test.dart`（8/8 通过）与 `test/os11_protocol_capability_test.dart`（7/7 通过）。
  - 模型发现身份由 `(provider, normalizedBaseUrl, protocol, credential)` 四元组锁定，URL 或协议切换立刻作废旧列表并取消在途请求，迟到响应严格丢弃不入缓存。
  - 三协议（OpenAI 兼容、OpenAI Responses、Anthropic Messages）差异化参数按规范注入；连接测试区分为端点鉴权、模型发现、生成测试三层，生成测试必须经用户二次确认才触发。
- **字号缩放与外观（OS18/OS19）**：
  - 运行 `test/os18_text_scaling_test.dart`（3/3 通过）与 `test/os19_affordance_test.dart`（11/11 通过）。
  - 设置页字号滑块预览在系统缩放（`TextScaler`）与应用自定缩放之间仅复合缩放一次，不再重复相乘。
  - 任务操作区与复选框满足最小 48dp 触摸/点击热区，提供完整的辅助功能语义（Semantics）。
- **桌面应用设置（OS14）**：
  - 运行 `test/os14_desktop_shell_test.dart`（7/7 通过）。
  - 开机自启、关闭到托盘、全局快捷键等设置通过 `DesktopShellService` 进行状态应用与代际追踪，失败时向 UI 报告明确错误并提供重试。

### 3.3 备份与持久化路径（Backup）

- **启动恢复与容灾（OS05）**：
  - 运行 `test/os05_startup_recovery_test.dart`（7/7 通过）。
  - 损坏的任务 JSON 或非法的 primitive 在启动时被标记为损坏，绝不会被静默初始化为 `[]` 覆盖；直接跳转到启动恢复页（`StartupRecoveryScreen`），允许导出故障前原始数据副本或显式清除。
- **事务性双槽保存协议与预检（OS06/OS07）**：
  - 运行 `test/os06_os07_transaction_test.dart`（12/12 通过）。
  - 每次保存（`Store.flush`）生成包含 Adler-32 校验与单调递增版本号的完整快照，在两个 SharedPreferences 存储槽之间轮替，只有指针写入成功才算提交完成；注入 `setString` 失败或中断时，重启能完整回滚至上一个有效快照。
  - 导入预检（`import_preflight.dart`）严格限制 4 MiB 大小、12 层嵌套、500 板 / 10000 任务 / 50000 子项上限，防止超大异常备份导致 OOM。
- **凭据隔离（OS08/OS09）**：
  - 运行 `test/os08_os09_credential_test.dart`（12/12 通过）。
  - 默认 JSON 备份（v1/v2）完全省略 `customApiKey` 字段；仅当用户在导出选项中显式选择“包含明文密钥”并确认风险提示时才导出密钥。
  - 运行 Windows 原生安全存储集成测试：
    `flutter test --no-pub integration_test/os09_secure_storage_test.dart`（1/1 通过）。
    验证了 Windows Credential Manager 的真实底层读、写、删操作无异常。

### 3.4 列表滚动与惰性构建性能实测（List Scrolling & OS22 Benchmark）

在 Windows 11 本机（AMD Ryzen 7 8845H，143.99 Hz 虚拟刷新率，帧预算 6945 µs）上，以 profile 模式运行官方性能基准工具：
`flutter run -d windows --profile -t tool/os22_perf_bench.dart --no-pub`
使用合成数据在内存模拟 SharedPreferences 下对 1000 任务与 10000 任务进行了真实测量，输出 JSON 报告：

| 测量场景 | 任务数 | 挂载 TaskCard 数 | 挂载 Element 数 | 首帧构建耗时 | 首帧 Total 耗时 | 一次 notify 重建 | 滚动 2400px (总帧数) | 滚动 Total p50 | 滚动 Total p90 | 滚动超预算帧数 (超标率) | 滚动后 RSS 内存 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **宫格 (grid-1k)** | 1,000 | 45 | 5,426 | 3.8 ms | 4.8 ms | 12.7 ms | 294 帧 | 2.53 ms | 3.20 ms | 1 / 294 (0.34%) | 148.6 MB |
| **列表 (list-1k)** | 1,000 | 24 | 3,104 | 3.1 ms | 3.9 ms | 9.2 ms | 308 帧 | 1.83 ms | 2.61 ms | 1 / 308 (0.32%) | 148.8 MB |
| **宫格 (grid-10k)** | 10,000 | 45 | 5,426 | 2.5 ms | 3.4 ms | 14.8 ms | 294 帧 | 2.56 ms | 3.21 ms | 1 / 294 (0.34%) | 168.6 MB |
| **列表 (list-10k)** | 10,000 | **24** | **3,104** | **2.9 ms** | **3.8 ms** | **11.2 ms** | **308 帧** | **1.83 ms** | **2.62 ms** | **1 / 308 (0.32%)** | **162.9 MB** |

**性能实测结论**：
1. **惰性构建确已生效**：在 1 万条合成任务的超大列表下，挂载的 `TaskCard` 卡片数量从修前的 2500 骤降为仅当前视口的 **24 张**（元素数仅 3104），避免了一次性把几千张卡片压入树中。
2. **超高刷新率下流畅稳定**：在 144 Hz（6.9 ms 严格预算）的显示器下，1 万条任务的列表滚动 2400 像素采样了 308 帧，total p50 为 **1.83 ms**，p90 仅 **2.62 ms**，p99 仅 **3.23 ms**；全流程超预算帧仅有 **1 帧**（超标率 0.32%）。
3. **内存控制优异**：1 万条任务滚动后的常驻内存集（RSS）稳定在约 163 MB（峰值 196 MB），无内存暴涨或泄漏。
4. **测量限制声明**：上述数据仅支持本 Windows 测试机环境与合成任务条件，**绝不能外推至 Android 设备的性能表现**。

### 3.5 窗口生命周期与单实例（Window Paths & Smoke Tests）

针对 Windows 平台的原生窗口管理、系统托盘、全局热键、协调退出与单实例保护，执行了 3 项独立的真实 Windows 进程烟雾测试（均使用内存/隔离 profile）：

1. **Windows 托盘与全局快捷键烟雾测试**：
   - 命令：`flutter run -d windows -t tool/os14_windows_shell_smoke.dart --no-pub`
   - 结果：`PASS tray=success hotkey=success reserved=conflict hide=ok recall=ok retry=ok`
   - 验证了窗口隐藏到托盘、托盘图标点击重新唤起窗口、安全全局热键（`Ctrl+Alt+Shift+9`）注册成功、以及保留系统热键（`Win+L`）冲突拦截与降级恢复。
2. **Windows 协调退出烟雾测试**：
   - 命令：`flutter run -d windows -t tool/os15_windows_exit_smoke.dart --no-pub`
   - 结果日志依次记录：
     `START isolated OS15 Windows exit smoke` → `EXIT requested` → `COORDINATOR started` → `COORDINATOR completed`，进程正常自行退出（exit 0）。
   - 验证了退出守卫统一等待任务保存与状态收尾后再销毁窗口。
3. **Windows 通知与托盘综合烟雾测试**：
   - 命令：`flutter run -d windows -t tool/os25_platform_smoke.dart --no-pub`
   - 结果：`PASS notification=shown tray=success profile=untouched`
   - 验证了本地 WinRT Toast 通知展示、托盘初始化与清理，且全程不碰用户任务库。
4. **单实例进程保护（OS16）**：
   - 自动化专项测试 `test/os16_single_instance_test.dart`（6/6 全部通过）。
   - 验证了 Windows runner 互斥量与受限命名管道对多实例竞争的拦截与参数中继。

---

## 4. 文档构建与测试命令核对

对现有文档（`README.md`、`matrixflow-native/README.md`、`docs/DEVELOPMENT.md`）中记载的开发与构建命令进行了逐一实测核查：

| 文档声明命令 | 实际执行环境 | 实测结果 | 审计意见与差异记录 |
|---|---|---|---|
| `flutter test --no-pub` | `matrixflow-native/` | **560/560 全部通过**（耗时 2分28秒） | 文档根 `README.md` 徽章标 328/328（系 UX05 历史数据），需 Agent A 更新为 560。 |
| `flutter analyze --no-pub` | `matrixflow-native/` | **0 issues**（耗时 9.0秒） | 与文档声明完全一致。 |
| `flutter test --no-pub integration_test/app_test.dart` | `matrixflow-native/` | **2/2 全部通过**（构建 82.5s，测试 3s） | 生产初始化与首次新手引导集成验证通过。 |
| `flutter test --no-pub integration_test/os09_secure_storage_test.dart` | `matrixflow-native/` | **1/1 全部通过**（构建 28.0s） | 原生安全存储探针验证通过。 |
| `flutter build windows --release` | `matrixflow-native/` | **成功构建**（耗时 104.3秒），产物位于 `build\windows\x64\runner\Release\matrixflow_native.exe` | 编译正常，无报错。 |
| `flutter build apk --debug` | `matrixflow-native/` | **成功构建**（耗时 87.7秒），产物位于 `build\app\outputs\flutter-apk\app-debug.apk` | 编译正常。Kotlin 增量缓存提示跨盘符（C:缓存与D:工程），Gradle 正常完成。 |
| `powershell -ExecutionPolicy Bypass -File scripts\build_release.ps1 -ValidateOnly -ExpectedTag v1.0.0+1` | 仓库根目录 | **退出码 0**，准确输出 tag 匹配、工具链核对、产物命名规划与缺失签名拦截信息 | 命令有效。支持 `-ExpectedTag v1.0.0` 与 `v1.0.0+1`。 |
| `powershell -ExecutionPolicy Bypass -File scripts\build_release.ps1 -ValidateOnly -ExpectedTag v2.0.0` | 仓库根目录 | **退出码 1**，明确拒绝：`pubspec.yaml declares 1.0.0+1. Refusing to stage a release whose tag and version disagree.` | 标签校验门禁生效。 |
| `powershell -ExecutionPolicy Bypass -File scripts\build_release.ps1 -Platform Android -ExpectedTag v1.0.0` | 仓库根目录 | **退出码 1**，拒绝构建：`Formal release signing credentials are required ... Refusing to build a debug-signed release APK.` | 正式签名拦截生效，防止未签名包误发布。 |

---

## 5. 公开状态声明核对

核对公开声明与当前代码仓库实际能力边界：

1. **版本阶段状态定位**：
   - **源代码准备阶段**：当前代码已完成 OS01–OS26 的全量治理，单元/组件测试达 560 项通过，静态分析 0 issues，工具链与本地构建脚本闭环。
   - **测试版（Beta）与发行状态**：
     - Android：目前仅具备 Debug APK 构建能力；正式 Release APK 严格受签名前置门槛保护（未配置正式证书时拒绝构建），**尚未进行正式 Android 签名**。
     - Windows：Release 可执行程序构建通过，但**未进行 Authenticode 代码签名**（NotSigned），在 Release 说明中必须如实披露。
     - 仓库状态：当前本地 Git 仓库**无远端（no remote）**，尚未推送至公共 GitHub/Gitee，GitHub Actions 托管 runner 从未在远端运行，未公开发布 Release。
   - 结论：**不得宣称“稳定发行版（Stable Release）已发布”**，应准确定位为“代码治理与开源发布就绪（Release-Ready / Open Source Candidate）”。
2. **隐私声明核对（Privacy Claims）**：
   - 根目录 `README.md` 原文存在“100% 本地优先与绝对隐私 (Local-First & Privacy-Centric)”的不准确表述。
   - 审计事实：虽然任务数据默认存储在本地 SQLite/SharedPreferences 沙盒中且无第三方埋点，但用户配置 BYOK（自带 API 密钥）后，应用会通过网络直接向用户所选的第三方 AI 服务商（DeepSeek、火山引擎、阿里云百炼、OpenAI 或 Anthropic）发送任务内容与提示词；同时用户导出备份时可自主选择是否包含明文密钥。因此应明确告知**“任务数据网络直连用户配置的模型端点，无中转中介，但非绝对物理隔绝”**，建议由 Agent A 删除“绝对隐私”等绝对化词汇。
3. **数据互通与兼容性（Lossless Claims）**：
   - `README.md` 原文存在“跨平台 100% 无损往返互通”表述。
   - 审计事实：正如 `BACKUP_FORMAT.md` 中所详述，从 v2 格式降级到旧版 v1 格式时会丢失多级子任务嵌套、部分状态标记以及凭据分离信息。不应宣称“通用 100% 无损”，应指明“标准 JSON 格式互通，向后兼容读取 v1，v2 提供完整数据保真”。
4. **测试数字与徽章**：
   - `README.md` 与 `matrixflow-native/README.md` 徽标仍显示 `328/328 Passed`（UX05 遗留），当前实际为 `560/560 Passed`。
5. **未决事项（F21/F22）**：
   - Android `applicationId` 仍为 `com.matrixflow.app`，正式签名密钥仍待项目持有人提供材料；文档与状态中不能假定其已解决。

---

## 6. Android 平台状态与设备边界

- **设备连接实测**：
  - 执行 `adb devices`：
    ```text
    List of devices attached
    (无任何设备连接)
    ```
  - 执行 `flutter devices`：仅识别到 Windows (desktop) 及 Chrome/Edge (web)，无 Android 物理设备或模拟器。
- **未测项（UNTESTED）明确清单**：
  - **Android 触控交互**：长按拖拽跨象限、卡片左右滑动完成/删除的手势触感未在真机检验。
  - **Android 软键盘与真实 IME 行为**：中文软键盘组字、软键盘弹起对任务输入框与并列详情的顶起遮挡表现未测。
  - **Android 物理列表滚动与惯性**：真机触屏滚动帧率与流畅度未测。
  - **Android 原生提醒闹钟与重启唤醒**：`SCHEDULE_EXACT_ALARM` 的真机弹出与开机广播未测。
  - **Android 覆盖升级**：新旧版本沙盒数据原位升级未测。
- **结论**：本报告中的所有流畅度与帧时间数据均来源于 Windows 11 桌面端，**明确不外推、不推断 Android 的表现**。

---

## 7. 提交与交接边界

1. **改动文件范围**：
   - 本包**仅新增** `docs/OS27_VALIDATION_NOTES.md`。
   - 生产代码（`lib/`、`android/`、`windows/`）、测试代码、Agent A 文件（`README.md`、`ARCHITECTURE.md` 等）及 Agent B 文件（`l10n.dart`、`onboarding_screen.dart` 等）完全未动。
   - `flutter pub get` 带来的 `windows/flutter/generated_plugin_registrant.*` 行尾差异不予暂存和提交。
2. **后续集成收口**：
   - 本记录提供全部客观验证数据与平台证据。
   - 最终 `AGENTS.md`、`HANDOFF.md`、`CHANGELOG.md` 及实施计划的状态收口由集成人在 A/B/C 三子批次完成后统一执行。
