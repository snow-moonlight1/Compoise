# RF10 平台定向验收记录（第一阶段：已集成的 RF02–RF07）

> 后续复核：本记录 A6 的 Android SAF “未测”已由 [Android SAF 单文件实测](RF10_ANDROID_SAF_NOTES.md)补齐。原机与模拟器均成功打开选择器、保存文件并导入；当时无可见反应主要由坐标未命中解释。本记录保留第一阶段原始观察，其他未测项仍以新记录和 HANDOFF 为准。

日期：2026-09-26。基线：`main / ac732b13b4488fd8751ebcf5bcb8c4736f882340`。
分支 `codex/rf10-platform-evidence`，工作树 `D:\Dev_project\martix-rf10-platform`。
范围：**只验收已集成的 RF02、RF03、RF04、RF05、RF06、RF07**。RF08（提醒重试边界）与 RF09（保存成本）尚未收口，本包不做其平台验收，最终 RF10 收口另行执行。
本包不改产品源码、不改共享 AGENTS/HANDOFF/CHANGELOG/返修计划，不与 RF08 并行修改 Store。

## 0. 结论速览

| 项 | 结果 |
|---|---|
| Windows Release 数据/凭据/导入/多卷备份/逐卷恢复 | **通过**（真实磁盘 + 真实 Windows 凭据存储） |
| Windows Release 超计数历史库恢复 | **失败（已知残余，实测确认）**：导出 2 卷，第 2 卷被拒，10599 中只恢复 7066 |
| Windows Release 退出时 applySettings 未完成 | **通过（实测三种交错均未重建托盘/热键）**，但源码无退出状态检查，且退出后 `isApplyingSettings` 残留为 `true` |
| Android Release 引导/软键盘/中文输入/批量添加/设置页渲染 | **通过** |
| Android Release SAF 导入导出、凭据跨重启、未提交子项、真实 IME 组字 | **未测**（原因见第 4 节，附人工清单） |
| Windows 原生文件对话框逐卷保存、聚焦手感、Windows 真实 IME | **未测**（本轮按要求不接管桌面输入） |

## 1. 环境与构建模式

- 宿主：Windows 11 企业版 10.0.26200 x64，桌面缩放 200%（物理 2560×1440 窗口）。
- 固定 SDK：`D:\Dev_SDKs\Flutter_3.32.8`，Flutter 3.32.8 / Dart 3.8.1（`dart=3.8.1 (stable) ... on "windows_x64"`）。
- **构建模式区分**：本包产物全部是 **Release 编译模式**。Windows 侧为本地构建的未签名 Release 可执行文件；Android 侧为 `flutter build apk --release`（本地开发签名，非 OS26 正式签名发行包）。三者与“Debug 开发包 / Release 性能测试包 / 正式签名发行包”不同，本包不宣称任何发行门槛。
- 产物指纹：
  - Windows Release（未改身份的正式构建）`matrixflow_native.exe` SHA-256 `ad8be0130619aa1c25797b70263f5d705a6d3bfceeaff149c9f04bf9f8923b2d`，`flutter build windows --release` 152.8s 成功。
  - 隔离验收副本（仅改身份字符串，见第 2 节）exe SHA-256 `aa36befba2e2d4810a2259b3724653b331ecc6855c9a968db6a15869744f1b24`。
  - Android Release APK `app-release.apk` 58,624,642 bytes，SHA-256 `7efa2c65d3defc67e863c658e9047728dffa0874ab628f18eeee387f5f9d5bb7`。
- 门禁复测（固定 SDK，基线原样）：`flutter test --no-pub` **700/700**，`flutter analyze --no-pub` **0 issues**。与 HANDOFF 顶部声明一致。

## 2. 隔离措施与用户数据保护（先声明，因为后续每项都依赖它）

1. **Windows**：验收不直接跑正式产物，而是从 `ac732b1` 用 `git archive` 导出到仓库外副本 `D:\Dev_project\_rf10\matrixflow-native`，只改两处身份：`windows/runner/Runner.rc` 的 `CompanyName`→`com.matrixflow.rf10review`、`ProductName`→`MatrixFlow RF10 Review`（`path_provider` 由版本资源推导数据目录），并把窗口标题改为 `MatrixFlow RF10 Review` 以便确认输入/截图目标。业务源码与 `ac732b1` 逐字节相同。
   - 结果：所有写入落在 `%APPDATA%\com.matrixflow.rf10review\MatrixFlow RF10 Review\`。
   - **用户真实资料前后核对**（本轮结束时再次核对）：
     - `shared_preferences.json` SHA-256 `583e07800e701415249a412aa1526c755332c52e654d4b2a9913134d292c9784`，mtime 仍为 `2026-09-25 22:05:53`；
     - `flutter_secure_storage.dat` SHA-256 `97226ddbc8e43a9fb4807042f039c4b74b00d171562bf391d0daff5c64335680`。
     - 两者与接手基线**完全一致，未被读取或改写**。
2. **Android**：设备 `87d18604`（model `23117RK66C`，Android 16，物理 1440×3200@560dpi，覆盖 1080×2400@420dpi）。验收包 `applicationId` 改为 `com.matrixflow.rf10review`、label 改为 `MatrixFlow RF10`，与用户已安装的 `com.matrixflow.app` **并存**，不覆盖、不 `install -r` 用户包、不清除用户应用数据。全程只用合成数据与 `http://127.0.0.1` 本地回环端点，未使用任何真实密钥。
3. **本轮不接管桌面鼠标键盘**（用户明确要求）。Windows 侧改用 Release 模式自动化 harness（真实平台通道、真实文件、真实 Win32 托盘/热键，输出文件证据）；Android 侧用 adb（screencap + input）。因此凡是只能靠“人手 + 肉眼 + 原生对话框”证明的项，本包一律记为**未测**而不是推断通过。
4. 设备侧被临时改动的项，测后已恢复并核对：输入法回到 `com.bytedance.android.doubaoime/.ImeService`；无障碍服务回到 `li.songe.gkd/...SelectToSpeakService`、`accessibility_enabled=1`（该自动点击服务会在 adb 测试期间随机点击界面，是本轮早期几次“莫名翻页/打开面板”的原因，故测试期间临时关闭）。

## 3. Windows Release 逐项实测

harness 源码在仓库外 `D:\Dev_project\_rf10\matrixflow-native\tool\`（本包不入库，见第 6 节），日志与备份文件在 `D:\Dev_project\_rf10\evidence\`。所有模式都从**清空后的隔离 profile** 启动，调用的是产品真实 `Store` / `SettingsBackupFlow` 之下的导出、预检、提交与凭据代码路径，落真实磁盘。

### W1 普通保存与 flush、重启读回 — 通过
- 步骤：建板 + 3 父任务×2 子任务（中日文标题与备注）→ `flush()` → 新建第二个 `Store` 读回。
- 预期：`SaveResult.success`，内存/磁盘/新 Store 三者一致。
- 实测：`PASS flush-small-library tasks=3 subtasks=6`；`PASS restart-readback-tasks memory=7 disk=7`。
- 证据：`evidence/windows-flows.log`。

### W2 凭据最后意图与重复值（RF03）— 通过
- 步骤：A→B→空 依次 `updateAIConfig` + `flush`；再连续两次写同一值；随后从真实 Windows 凭据存储读回。
- 预期：最后意图生效；清空后保护存储无值；重复值仍精确落盘一次。
- 实测：`PASS credential-last-intent-empty secureStorage=null`；`PASS credential-repeat-value flush=true readMatch=true`；`PASS restart-readback-credential`。
- 证据：同上。

### W3 导入与普通命令共用提交顺序（RF02）— 通过
- 步骤：把导出的备份改写成“异地库”（新 id/新标题）→ `previewImport(merge)` → **预览之后再**新增一条本地任务 → `applyImport` → `flush` → 重启读回。
- 预期：预览后接受的编辑不被旧预览覆盖；异地记录与本地编辑同时存在；失败不部分改库。
- 实测：`PASS import-accepts-foreign-records plannedAdded=3`；`PASS import-with-concurrent-edit localEditKept=true foreignKept=true total=7`；`PASS restart-readback-tasks memory=7 disk=7`。
- 证据：同上。

### W4 默认导出与凭据边界（RF04/RF03）— 通过
- 实测：`PASS export-single-part`（小库单文件）；`PASS exported-file-passes-restore-gate`（导出文件能过与恢复相同的门禁）；`PASS default-export-omits-key`（默认备份不含密钥）；`PASS export-with-credential-carries-key`（显式含密钥时写入且只写一次）。
- 证据：`evidence/windows-flows.log`、`evidence/flows-single.json`（2689 bytes）。

### W5 多卷连续保存（RF04）— 通过
- 步骤：6 个板 × 600 任务（含中日文长备注）→ 文档实测 15,333,054 bytes → `exportBackup()` → 逐卷写真实文件。
- 预期：超过单文件上限才分卷；每卷都在可读取上限内；只有第 1 卷携带设置与 AI 配置。
- 实测：`PASS export-split parts=7`；7 个真实文件 `volumes-matrixflow_backup_rf10_part1of7.json` … `part7of7.json`，各约 2.19 MB；`PASS all-parts-within-file-ceiling`（`maxFileBytes=8388608`）；`PASS only-first-volume-carries-config`。
- 重要澄清：第一次尝试用 5.46 MB 库时期望分卷，实际得到**单文件**——因为 4 MiB 是**内容预算**、8 MiB 才是**文件上限**，5.46 MB 未超文件上限属正确行为（记录为“预期写错”，不是产品缺陷）。
- 证据：`evidence/windows-volumes.log` 与 7 个卷文件。

### W6 逐卷恢复（RF04）— 通过
- 步骤：清空隔离 profile → 按界面提示顺序（第 1 卷覆盖、其余合并）逐卷 `previewImport`+`applyImport`+`flush` → 重启读回。
- 预期：全部成功导出的受支持备份都能在新库里完整恢复。
- 实测：`restore-starts-empty` → 7 卷各 `added=600 skipped=0 apply=true flush=true`，累计 600→4200；`PASS restore-all-volumes-in-order finalTasks=4200`；`PASS restore-survives-restart memory=4200 disk=4200`；`PASS restore-content-intact boards=7 subtasks=8400`。
- 证据：`evidence/windows-restore.log`。

### W7 超计数历史库（RF04 残余）— 失败/限制，如实记录
- 步骤：直接经 `Store` 造出 **10,599** 条任务（超过受支持上限 10,000）→ `flush` → `exportBackup()` → 写真实卷文件 → **清空 profile** → 按提示顺序逐卷真实恢复。
- 预期（若契约成立）：能完整恢复。
- 实测：导出成功且 `recoverable=true`，得 2 卷（3,790,345 + 1,903,733 bytes）；恢复时第 1 卷覆盖成功（7,066 条），第 2 卷合并被门禁拒绝：`Import would exceed the supported library limits`；最终 `FAIL overcount-library-fully-restorable refusedAtVolume=2 restored=7066 of 10599`；失败后库保持一致 `PASS overcount-refusal-left-library-consistent memory=7066 disk=7066`。
- 结论：**“所有成功导出的备份都能恢复”不成立**，仅对受支持计数内的库成立。已超计数上限的历史库可被完整导出，却无法按官方逐卷流程无损一键恢复（约 1/3 数据留在备份文件里）。要消除该限制需单独决定“受支持计数上限”是否上调或提供分卷合并例外，属产品决策，不在本包修改。
- 证据：`evidence/windows-overcount.log`、`evidence/windows-overcount-restore.log`、`overcount-*_part1of2.json`/`part2of2.json`。
- 方法学更正：本项第一版实现把每一卷单独对着空库过门禁，得出“2/2 可恢复”的错误结论；已改为按真实顺序累加结果库重跑，上述数字来自重跑。

### W8 退出时 applySettings 未完成（额外核对项）— 通过，附两项告警
- 工具：`tool/rf10_exit_race.dart`，用**真实** `WindowsDesktopShellHost`（真实 `Shell_NotifyIcon` 与真实 `RegisterHotKey`）外包一层调用记录器，观察 `start/registerHotkey/destroy` 的时序；退出守卫用 250ms 等待模拟 `Store.flush` 屏障。
- baseline（apply 完成后再退出）：`T+445 start(tray)` → `T+468 registerHotkey` → `T+720 destroy BEGIN` → `T+725 destroy END` → `exitApplication -> completed` → `trayInitialized=false registered=null` → **进程 12s 内自行退出**。
- race（第二个 apply 不等待，立即退出）：第二个 `start(tray)` 发生在 `T+750`，**在 destroy（T+1002）之前**完成，随后 destroy 正常清掉托盘与热键，`destroy` 之后没有任何 `start/registerHotkey`，进程自行退出。
- race2（把第二个 `start()` 人为挂起 600ms 跨过 destroy 边界）：挂起的续体还没回来，窗口已销毁、进程已终止（仍 `self-exited-within-12s=True`），因此也没有出现“退出后托盘复活”。
- 实测结论：**三种交错下都没有重新创建托盘或重新注册热键**，用户可见行为正确。
- 告警 1（源码层面，非本包修复范围）：`_applySettingsNow` 只比较 `generation`，从不检查 `_hasExited`/`_exitInFlight`，且 `_performExit` 在 `destroy()` 前把 `_host` 置空、`_host ??= _hostFactory()` 会**新建 host**。当前之所以没出问题，靠的是“窗口销毁即进程终止”这一时序，而不是显式防护；一旦退出路径不再立即终结进程（例如改为可取消退出或 destroy 失败重试），排队中的 apply 就可能重建托盘/重绑监听/重注热键。建议后续包补一个退出状态检查。
- 告警 2（可观察的小缺陷）：race2 中退出完成后 `post-exit state: ... applying=true`，即 `isApplyingSettings` 在退出后仍为 `true` 未收口（`_publish` 因代际/退出路径没有走到复位）。目前无用户可见后果，但状态与真实情况不一致。
- 证据：`evidence/windows-exit-baseline.log`、`windows-exit-race.log`、`windows-exit-race2.log`。

### W9 Windows 聚焦 / 键盘 / 真实 IME / 原生文件对话框逐卷保存 — 未测
- 原因：这些只能靠真实桌面输入与肉眼判断（焦点环观感、微软拼音组字过程、另存为对话框逐卷点按）。本轮用户明确要求不得接管其桌面鼠标键盘，本包因此**停在这几项**，不用 widget 测试或构建成功冒充。
- 已确认的相关事实（不是验收结论）：Release 产物无控制台输出（`main.cpp` 仅在父控制台存在或调试器下附加），导出/导入/凭据路径也没有 `print/debugPrint`，所以外部观察只能靠界面与文件；本轮用真实文件写入覆盖了“多卷连续保存”的字节与命名契约，但**未**覆盖“用户在另存为对话框里逐卷点按”的交互路径。
- 人工验收清单见第 5 节。

### W10 AI 设置页思考开关与部分成功提示（RF06）— Windows 未测
- 逐型号提示文案与探测分类由 RF06 的 `test/rf06_model_capability_rules_test.dart` 35 项覆盖（本包复跑全量 700/700 含之），但 Windows 设置页上“思考开关副标题、`aiGenerationPartial`/`aiGenerationThinkingOnly` 的实际显示”未经肉眼确认；本包未用真实厂商凭据，也未向任何外部端点发请求。
- Android 侧的对应观察见 A5（部分文案已实机看到）。

## 4. Android Release 逐项实测

设备 `87d18604`，包 `com.matrixflow.rf10review`（Release 模式，本地开发签名），与用户 `com.matrixflow.app` 并存。

### A1 构建与安装 — 通过
- `flutter build apk --release` 成功（首次因 Kotlin 守护进程跨盘增量缓存报错中断，Gradle 回退后 `BUILD SUCCESSFUL in 6m 6s`，与 AGENTS 记录的已知现象一致）。
- `adb install -r` 首次返回 `INSTALL_FAILED_USER_RESTRICTED`（MIUI 门禁），屏幕点亮后重试 `Success`；`pm list packages` 显示两个包并存，用户包未被替换。

### A2 首次运行引导 — 通过
- 步骤：`pm clear` 我的包 → `am start` → 每秒截图。
- 实测：第 1 页“四象限矩阵与快速添加”正常显示，中文换行、四象限示意卡、Material 图标（宫格、下拉、对勾、加号、铃铛、垃圾桶、扩展箭头）**均正常渲染，无方框**；`跳过` 与 `下一步` 可点，走完 4 页后进入主界面。
- 说明：早期两次“引导莫名翻页并弹出看板面板”的截图，原因是该机上启用的 GKD 无障碍自动点击服务在随机点击，不是应用缺陷；关闭该服务后同一操作序列稳定（`g1`/`g2` 两张截图字节级一致）。
- 证据：`shots/f1.png`、`g1.png`、`j2-matrix.png`（截图按用户要求本轮结束后删除，此处仅记录观察）。

### A3 软键盘与输入区遮挡 — 通过
- 步骤：主界面 `添加任务` → 快速添加面板 → 输入法弹出。
- 实测：面板整体抬到键盘之上，`普通添加/AI 智能分类` 两个页签、输入框、`今天/明天/选择日期`、`设置提醒`、`确认添加` 全部可见可点，无遮挡、无溢出。
- 证据：`shots/k1-addsheet.png`。

### A4 中文输入与多行批量添加 — 通过（含一次意外）
- 实测：中文/反斜杠/多行文本经输入法进入输入框并提交后，主界面 `紧急且重要` 一次生成 **3 条**任务（快速添加的换行批量语义在 Android Release 生效），象限计数由 0 变 3。
- 诚实说明：这 3 条文本来自输入法候选条上的**剪贴板建议**被我误触插入（内容是本机剪贴板里的派单文字，与产品无关，也不写入本记录）。它仍然证明了 CJK 输入、多行批量、持久化与列表刷新。测后我已 `pm clear` 我的包，未留下这批数据。
- 证据：`shots/m1-candidates.png`。

### A5 设置页与 AI 区块渲染（RF05/RF06 相关）— 部分通过
- 实测可见：`显示/语言(EN·中文·日本語)`、`主题`、`任务行为` 各开关与说明、`紧急阈值` 滑杆、`AI 提供商`（DeepSeek 下拉 + `API 地址 https://api.deepseek.com` + `API 密钥 sk-…` 输入框）、`高级设置` 折叠、思考提示“DeepSeek 默认使用 deepseek-flash；可在设置中调整模型和思考模式”、连接三行 `端点与鉴权: 未检查` / `模型发现: 未检查` / `所选模型生成: 尚未测试所选模型生成。模型列表成功不等于可以生成。`、`测试连接` 与 `测试所选模型生成` 两个按钮，以及“生成测试可能产生费用，只有在你确认后才会发送。”
- 判定：连接面板与费用确认文案在 Android Release 上渲染正确（RF05/RF06 的 UI 侧证）；**未**逐项切换型号验证思考开关副标题与部分成功提示，也未发起任何真实请求。
- 证据：`shots/q1-settings.png`、`q4.png`、`s2-advanced.png`。

### A6 SAF 导入 / 导出文件流程 — 未测（受阻，需人工）
- 步骤：把 Windows 侧产出的 `flows-single.json` 推到 `/sdcard/Download/rf10-from-windows.json`（2689 bytes，已 `adb shell ls` 确认）→ 设置 → 数据备份 → 点 `导出数据 (JSON)` / `导入数据 (JSON)`。
- 实测：在确认按钮位置正确（先展开 `高级设置` 导致布局位移，校正坐标后重按）的情况下，多次点按**均无任何对话框或 SnackBar**，界面保持原样；离开设置页重进后再试仍无响应；`logcat` 无 Flutter/file_picker 相关输出。
- 两种候选解释，本包未能区分：(a) 更早一次点按已让 `SettingsBackupFlow` 进入 `_busy` 而 SAF 选择器未真正弹出，导致后续按钮被 `disabled`（`_start()` 直接返回 cancelled，无提示）；(b) 我的点按仍未命中真实热区。二者都需要肉眼/人手确认，故本项记为**未测**，不写成失败也不写成通过。
- 为什么这项重要：`settings_backup_flow.dart` 的 `_writeBackupFile` 在 Android 上**故意不写字节**（依赖 file_picker 的 SAF 自行落盘），注入式写入器的单测覆盖不到这条真实路径。
- 人工步骤见第 5 节。

### A7 凭据写入 Android 保护存储并跨重启（RF03）— 未测
- 依赖在设置页输入密钥（A6 同页受阻于点按），且 Release 包不可 `run-as`，无法从外部读取其私有目录核对；本包未做，不用 Windows 侧的 W2 结果外推。

### A8 未提交子项的关闭与任务切换（RF07）— 未测
- 需要进入任务详情面板输入子项但不点“添加”，再关闭/切换任务观察草稿行为。本轮未完成（先要能稳定创建任务；A4 的批量任务已在清数据时移除）。

### A9 真实输入法组字过程（RF07）— 未测
- `adb shell input text` 直接把字符提交到输入框，**绕过输入法组字**（实测字段里出现的是原始拼音字母 `jintianxiawu`，没有候选与下划线）；改用屏幕坐标点按虚拟键盘虽然会经过输入法，但会命中输入法的候选/剪贴板建议条（见 A4），无法可控地构造“组字中未提交”状态。因此 composing 行为仍只有 RF07 的单元/widget 层证据。

### A10 提醒（RF08 相关）— 不在本包
- RF08 源码尚未收口，本包不做 Android 排程/取消与 Windows 运行中提醒的验收。

## 5. 交回用户的人工验收清单（只需肉眼 + 手，约 15 分钟）

Windows（用 `D:\Dev_project\martix-rf10-platform\matrixflow-native\build\windows\x64\runner\Release\matrixflow_native.exe`，它会写到 `%APPDATA%\com.matrixflow\MatrixFlow AI\` —— **先备份你自己的 `shared_preferences.json`**，或改用我的隔离副本）：
1. 聚焦/键盘：Tab、Shift+Tab、方向键、Enter、Esc 遍历四象限与卡片，确认焦点环可见、退场与隐藏子树不抢焦点。
2. 真实 IME：微软拼音组字过程中点保存/按回车，确认半截输入不入表；未点“添加”的子项在关闭与切换任务时的草稿行为符合预期。
3. 多卷：造一个超过 8 MiB 的库导出，在“另存为”里逐卷保存，确认文件名 `..._part{i}of{n}.json` 与提示文案；再在空 profile 按提示顺序逐卷恢复。
4. 退出：切换托盘/快捷键开关的同时点关闭，确认没有残留托盘图标或热键（可用其它程序注册同一组合键试探）。
5. AI 设置页：逐型号看思考开关副标题与探测结果文案（含部分成功）。

Android（隔离包 `com.matrixflow.rf10review` 仍装着，可直接用；测完可 `adb uninstall`）：
1. 设置 → 数据备份 → `导出数据 (JSON)`：确认 SAF 保存对话框出现，落到 Downloads 后 `adb pull` 校验字节数与内容。
2. `导入数据 (JSON)`：选 `/sdcard/Download/rf10-from-windows.json`（Windows 产物，验跨端互通），确认“导入选项 → 预览 → 确认”，并核对任务数。
3. 若两者点下去毫无反应，即为 A6 的可复现证据，请告诉我，我按缺陷立案。
4. 填一个合成密钥（如 `RF10-SYNTH-0001`）→ 杀进程重启 → 看密钥是否仍在；再默认导出一份，确认 JSON 里没有该密钥。
5. 未提交子项：详情面板输入子项文字但不点添加 → 关闭 → 打开另一任务，确认不带过去、不静默丢失。

## 6. 本包边界与产物位置

- 仓库内**只新增本文件**。未改 `lib/`、`test/`、`android/`、`windows/`、AGENTS/HANDOFF/CHANGELOG/返修计划，未与 RF08 并行触碰共享 Store。
- `flutter pub get` 带来的 `windows/flutter/generated_plugin_registrant.{cc,h}`、`generated_plugins.cmake` 三处行尾差异按既往惯例**不纳入提交**。
- 验收 harness（`tool/rf10_windows_flows.dart`、`tool/rf10_exit_race.dart`）与 PowerShell/adb 驱动放在仓库外 `D:\Dev_project\_rf10\`，刻意不入本分支：它们改过身份字符串的副本、也会与产品 `tool/` 目录混淆。若集成人认为值得沉淀为可复跑的验收工具，可另行决定放置位置。
- 日志与备份产物：`D:\Dev_project\_rf10\evidence\`（`windows-*.log` 8 份、7 个多卷文件、2 个超计数卷、1 个单文件备份）。
- 文中 `shots/*.png` 是本轮从设备/桌面拉取的临时截图，**收尾时已按要求全部删除**，因此这些路径只作观察来源的历史标注，不再可查；可复核的客观证据以 `evidence/` 下的日志与备份文件为准。
- 未做：签名、发布、push、切换 `main`；设备上的输入法与无障碍设置已恢复原值；我的隔离实例已关闭。
