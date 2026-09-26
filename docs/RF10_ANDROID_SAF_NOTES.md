# RF10 Android SAF 导入/导出定位记录（A6 复盘）

日期：2026-09-26。基线提交：`main / 76a8201f460293f46abc52d32e50165e1670bce2`。
分支 `codex/rf10-android-saf`，工作树 `D:\Dev_project\martix-rf10-android-saf`。固定 SDK `D:\Dev_SDKs\Flutter_3.32.8`（Flutter 3.32.8 / Dart 3.8.1）。
范围：只处理 [RF10 第一阶段](RF10_PLATFORM_EVIDENCE.md) 第 4 节 A6 记录的“设置页导入/导出点按后没有可见 SAF 对话框”。本包**不改产品源码、不加测试、不改共享文档**，只新增本文件。

## 0. 结论速览

| 项 | 结果 |
|---|---|
| Export JSON 点按后是否出现 Flutter 凭据对话框 | **出现**（模拟器 Android 15 与 A6 原机 Android 16 均复现） |
| 选择“不含密钥”后是否出现 SAF 保存对话框 | **出现**（A6 原机为 `com.google.android.documentsui` 的 `PickActivity`） |
| 导出文件是否真的落盘 | **是**：原机 `/sdcard/Download/matrixflow_backup_2026-09-26.json` 755 bytes，SHA-256 `F60502A9EF8ECB9C6B7110A434BB80D6CD65BA5DEB7B040E503D0CFEF8E91826`；模拟器 751 bytes，SHA-256 `B59D8261E55E437FA3EBE6583FB0219D7DAD2A96AB9B64A00AECE20D770013CE` |
| Import JSON 选文件 → 预览 → 确认 → 重启读回 | **通过**（双端；原机重启后看板 `RF10SAF Synthetic` 内“紧急且重要 1 / 紧急但不重要 1”） |
| “按钮未命中” | **可复现**，且是唯一能在真实设备上复现 A6 指纹的路径之一 |
| `SettingsBackupFlow.busy` 未释放 | **未复现**；成功/取消/取消选择器四条终止路径后按钮都恢复可用，且首击前就是可用状态 |
| `FilePicker` 未启动 | **未复现**；插件被真实调用并拿到系统选择器结果 |
| 系统选择器未显示 | **未复现**；保存走 DocumentsUI，选择走 MIUI 文件管理器，两者都出现 |
| 是否存在需要修改 `settings_backup_flow.dart` 的源码缺陷 | **未确认，因此未改**（理由见第 6 节） |

## 1. 构建模式、隔离与用户数据保护

1. **构建模式**：本包全部结论基于 **Release 编译模式**的 APK（`flutter build apk --release`，58,788,492 bytes，SHA-256 `E31EFB131F8ECA92F50895B18ED86A57BBD789528756F082217502E3986A9CFC`，本地 debug 签名）。不是 Debug 包，也不是 OS26 正式签名发行包。
2. **隔离副本**：`git archive 76a8201` 导出到仓库外 `D:\Dev_project\_rf10saf\matrixflow-native`，只改两处身份：`android/app/build.gradle.kts` 的 `applicationId` → `com.matrixflow.rf10saf`、`AndroidManifest.xml` 的 `android:label` → `MatrixFlow RF10SAF`。业务源码与 `76a8201` 逐字节相同。
3. **未覆盖用户包**：原机 `com.matrixflow.app` 全程未安装/未更新/未清除，测后核对 `versionName=1.0.0`、`firstInstallTime=2026-09-19 16:30:26`、`lastUpdateTime=2026-09-25 22:25:35` 不变。上一阶段遗留的 `com.matrixflow.rf10review` 也保持原状。
4. **未读取用户资料**：只推入自建的无密钥合成备份 `rf10saf-synthetic-backup.json`（787 bytes），全程无真实密钥、无外部 AI 请求。原机 Downloads 里用户自己的 `matrixflow_backup_2026-09-08.json`（6900 bytes）只出现在选择器列表里，未打开、未改、测后仍在。
5. **测后恢复**：原机卸载隔离包（`Success`）、删除本轮推入/导出的两个文件、按 HOME 回到桌面；`font_scale=1.0`、无障碍服务（`li.songe.gkd/...SelectToSpeakService`）、默认输入法（`com.bytedance.android.doubaoime/.ImeService`）在测试前后一致，本轮未改动这些设置。原机现有的 `wm size 1080x2400` / `wm density 420` 覆盖是**上一阶段遗留**，本轮按“按原样保留”处理，未重置（命令：`adb shell wm size reset` / `wm density reset`，由用户决定是否恢复）。
6. **未接管用户桌面输入**：本轮没有在 Windows 桌面点击或输入；设备侧只通过 `adb input` 操作隔离包界面。

## 2. 源级分析：四种可能如何区分

代码事实（`lib/screens/settings_backup_flow.dart`、`lib/screens/settings_screen.dart`）：

- `export()` 的第一件事是 `_start()`，**第二件才是 `showDialog`（凭据选择）**；`importBackup()` 的第一件事是 `_start()`，第二件是 `FilePicker.pickFiles`。
- `_start()` 只在 `_busy || _closed` 时返回 `false`，此时直接返回 `BackupOutcome.cancelled`，其 `message` 为 `null`，而 `_runExport`/`_runImport` 只在 `message != null` 时弹 SnackBar。**所以“busy 或 closed 时点按钮”= 无对话框、无 SnackBar、无插件调用、界面不变。**
- 按钮：`onPressed: _backup.busy ? null : ...`。Flutter `ButtonStyleButton` 的 `enabled => onPressed != null || onLongPress != null`，并以 `Semantics(enabled: widget.enabled)` 暴露（`Flutter_3.32.8/packages/flutter/lib/src/material/button_style_button.dart:589,241`）。因此无障碍树里的 `enabled=true` **等价于** `busy == false` —— 这给了一个不改代码就能观测 `busy` 的探针。
- 插件侧（`file_picker 8.3.7`）：`saveFile` 在 Android 走 MethodChannel `save` → `FilePickerDelegate.saveFile` → `ACTION_CREATE_DOCUMENT`；`pickFiles(custom, ['json'])` 走 method `custom` → `ACTION_OPEN_DOCUMENT` + `EXTRA_MIME_TYPES=["application/json"]`。两条路径进入原生后都会打 `Log.d`（`FilePickerUtils: Allowed file extensions mimes: ...`、`FilePickerDelegate: Selected type ...`）。
- `FilePickerDelegate` 用 `setPendingMethodCallAndResult` 做单飞：上一次 `pendingResult` 未回收时新调用立刻返回 `already_active` 错误 → Dart 侧抛 `PlatformException` → 被 `settings_backup_flow.dart` 的 `catch (_)` 吞掉并显示 `exportError`/`importError` SnackBar。**即“插件已启动但失败”会留下可见 SnackBar，不会静默。**

由此四类可能的判据：

| 可能 | 可观测特征 | 本轮观测 |
|---|---|---|
| 按钮未命中 | 无对话框、无 SnackBar、无插件日志、按钮 `enabled=true` | 见第 5 节，**可在真机复现** |
| `busy` 未释放 | 同上，但按钮 `enabled=false` | 四类终止路径全是 `enabled=true`；首击前也是 `enabled=true` |
| FilePicker 未启动（异常/未注册/`already_active`） | 有 SnackBar（`exportError`/`importError`） | 未出现；反而观察到插件日志与系统选择器 |
| 系统选择器未显示 | 插件日志出现但焦点未离开应用 | 焦点确实转到 `documentsui` / MIUI 文件管理器 |

## 3. 首击前状态与终止路径（`busy` 是否释放）

在同一页面上，用无障碍树读按钮 `enabled`：

- 首次进入“设置 → 数据备份”，`导出数据 (JSON)` / `导入数据 (JSON)` 均 `enabled=true` ⇒ `busy == false`。
- 导出成功落盘后：两者 `enabled=true`（`_finish()` 正常收尾）。
- 在凭据对话框按“取消”：两者 `enabled=true`。
- 在 SAF 保存/选择器按返回取消：两者 `enabled=true`。
- 导入成功（预览 → 确认）后：两者 `enabled=true`。

`_busy` 残留只可能来自一个永不完成的 await（插件 `pendingResult` 永远不会被投递，例如选择器尚未返回时宿主 Activity 身份被替换）。本包没有构造出该状态：`MainActivity` 的 `configChanges` 已含 `fontScale|screenLayout|density|uiMode`，常见“改设置触发重建”的路径不会重建 Activity。

## 4. 模拟器实测（Android 15 / AOSP DocumentsUI）

AVD `matrixtest`（`system-images;android-35;google_apis_playstore;x86_64`，Pixel 5，实际 1080×2340 @440dpi），以 `-no-window -gpu swiftshader_indirect -feature -Vulkan` 无窗口启动，用 `adb input` + `uiautomator dump` 驱动。

1. 导出：点 `Export JSON`（命中区 `[44,2132][526,2264]`）→ 2 秒内出现凭据对话框；选 `Exclude API key` → 焦点转到 `com.google.android.documentsui/.picker.PickActivity`，文件名预填 `matrixflow_backup_2026-09-26.json`（与 `backupFileName` 一致）→ 点 SAVE → 焦点回到应用。
   - 落盘：`/sdcard/Download/matrixflow_backup_2026-09-26.json` 751 bytes。
   - 内容：`version=2`、单看板、`tasks=[]`、`settings.language=en`，**`aiConfig` 不含 `customApiKey` 键**（OS08 默认契约在此真机路径成立）。
2. 导入：点 `Import JSON` → DocumentsUI 列出两个 JSON → 选合成文件 → 应用内出现“Import Options”(Merge/Overwrite) → 选 Merge → “Review import” 显示 `Boards to add: 1 / Tasks to add: 2 / Skipped 0 / Conflicts 0 / Warnings 0 / Settings included: No / AI configuration included: No` → 点 Confirm → SnackBar `Data imported! (2)`。
3. 冷启动读回：`am force-stop` + `am start` 后，看板 `RF10SAF Synthetic` 存在，`Urgent and Important = 1`（`Synthetic task one`）、`Urgent but Not Important = 1`（`Synthetic task two`），与合成备份完全一致。
4. 插件日志（模拟器 logcat 可见）：`FilePickerUtils: Allowed file extensions mimes: [application/json]`、`FilePickerDelegate: Selected type */*`、`FilePickerUtils: Caching from URI: content://com.android.providers.downloads.documents/...`。
5. 计时观察：DocumentsUI 冷启动 `ActivityTaskManager: Displayed ... +4s802ms`，即点按到选择器可见可能长达数秒，而应用在这段时间里**没有任何进度提示**，只有按钮被禁用（线条按钮的禁用态在视觉上并不显眼）。

## 5. A6 原机实测（87d18604，Android 16 / HyperOS）

安装隔离包 `com.matrixflow.rf10saf` 后，**用同一台设备重走 A6 步骤**：

1. 定位：设置 → 数据备份 → 两个按钮 `enabled=true`，命中区 `导出数据 (JSON)` `[42,2131][527,2257]`、`导入数据 (JSON)` `[553,2131][1038,2257]`（高 126 px）。
2. **单次**点 `导出数据 (JSON)` → 立即出现 Flutter 对话框“备份凭据 / 包含 API 密钥的备份是明文文件…” ⇒ **按钮与对话框都正常**。
3. 点“不包含 API 密钥” → 出现 SAF 保存对话框（MIUI 的“下载内容”，文件名预填 `matrixflow_backup_2026-09-26.json`，右下“保存”）⇒ **A6 说“没有可见 SAF 对话框”在原机上不可复现**。
4. 点“保存” → 焦点回应用 → `/sdcard/Download/matrixflow_backup_2026-09-26.json` 755 bytes（SHA-256 见第 0 节），内容为合法 v2、单看板“我的任务”、`tasks=[]`、无 `customApiKey`。
5. 导入：点 `导入数据 (JSON)` → 出现的是 **MIUI 自己的文件管理器** `com.android.fileexplorer/.picker.PickMainNavigatorActivity`（标题“安全访问”），且：
   - 默认停在“最近”标签，显示 **“没有文件”**；“文档”分类同样“没有文件”；
   - 必须切到“浏览” → `Download`，**向下滚动**才能看到 `matrixflow_backup_2026-09-26.json` 与 `rf10saf-synthetic-backup.json`；
   - 点选文件后不会立即返回，还需再点右下“**确定**”（`预览(1/100)` → `确定` 才可用）。
6. 选择合成文件 → 应用内“导入选项”（合并到当前 / 覆盖所有）→ “预览导入” `新增任务板: 1 / 新增任务: 2 / 跳过 0 / 冲突 0 / 修复 0 / 警告 0 / 包含设置: 否 / 包含 AI 配置: 否` → “确认” → SnackBar **数据导入成功！(2)**。
7. 冷启动读回：`am force-stop` + `am start` 后切到看板 `RF10SAF Synthetic`，`紧急且重要 = 1`（`Synthetic task one`，带 1 个子项）、`紧急但不重要 = 1`（`Synthetic task two`）⇒ **跨重启读回通过**。

设备特有的两点差异（都对“看起来没反应”有贡献，值得写进后续人工清单）：

- **保存与选择走的是两个不同应用**：保存 → AOSP `com.google.android.documentsui`；选择 → MIUI `com.android.fileexplorer`。按 A6 的描述去找“SAF 对话框”的人，看到 MIUI 风格、标题“安全访问”、且首屏是空的“最近”，很容易判断成“没弹出选择器”。
- **选择是多选式两步**：选中文件后还要按“确定”，这与 AOSP DocumentsUI 单击即返回不同。

## 6. A6 指纹的可复现解释与“为什么不改源码”

A6 记录的完整指纹是：**无任何对话框、无 SnackBar、界面保持原样、logcat 无 file_picker 输出、离开重进仍无响应**。本轮在真机复现出的、能同时满足前三条的路径有两条，都不需要产品缺陷：

1. **点按没有落在命中区**（更可能）。按钮命中区只有 126 px 高，且在展开“高级设置”后整块会下移；A6 自述正是“先展开高级设置导致布局位移，校正坐标后重按”。本轮我自己也犯过一次同类错误并留下了证据：模拟器上按截图比例推算出的 `More` 纵坐标 (y=2288) 已经落在其命中区 `[713,2131][1058,2263]` 之外，按下去完全无反应；改用以 `uiautomator dump` 的 `bounds` 中点后一次命中。**落空的点按不产生对话框、不产生 SnackBar、不产生插件日志——与 A6 的描述逐条吻合。**
2. **同一次尝试里的第二次点按吃掉了凭据对话框**。凭据对话框是 `showDialog` 默认 `barrierDismissible: true` 的模态框，屏障覆盖全屏；此时按钮已经 `busy` 并被禁用，但**屏障会把落在按钮位置的第二次点按解释成“点外取消”**，`includeCredential == null` → `cancelled` → `message == null` → 什么都不显示。本包在模拟器上复现了这一点：对 `Export JSON` 连续两次点按（间隔约 0.1 s 与 0.5 s 各一次），之后截图与无障碍树都显示页面原样、无对话框、无 SnackBar、无 SAF、无 file_picker 日志。

至于 `_busy`/`_closed` 残留与插件失败：前者需要“永不完结的 await”，后者会给出 SnackBar；两者本轮都没有观测到，也没有找到可复现路径。**因此没有确认的源码缺陷**，按任务约定不改 `settings_backup_flow.dart` 及其 Android 适配层，也不新增默认回归。

一个必须记录的方法学更正：**A6 里“logcat 无 file_picker 相关输出”在这台设备上不能作为证据**。实测该机 `logcat -d --pid=<应用 pid>` 完全为空，`-b main` 尾部只有系统进程（如 `AudioFlingerImpl`）的 `D` 行，第三方应用的 `Log.d` 整体不可见；而同一时刻插件确实已运行、系统选择器确实已弹出。换句话说，这台 HyperOS 设备屏蔽第三方日志，使“日志缺失”既可能是“没调用”，也可能是“调用了但看不见”。

## 7. 未测项（不推断通过）

- **原机上的多卷（分卷）SAF 导出**：只测了单文件（751/755 bytes）。超过 8 MiB 的库按 `part{i}of{n}` 逐卷保存需要库大于单文件上限，本轮未构造。
- **原机上的超计数拒绝界面**（`exportErrorTooManyRecords` 等）与导入越界拒绝：未测。
- **Windows 端**：本包不涉及，原生“另存为”逐卷保存与真实 IME 仍为 RF10 第一阶段第 9 节的未测项。
- **A7/A8/A9 相关**：凭据跨重启、未提交子项草稿、真实输入法组字，本包未测（本轮原机只做了默认导出与合成数据导入，未写任何密钥）。
- **A6 原始现场无法复原**：无法得知当时那几次点按的实际坐标与间隔，因此“命中偏差”与“二次点按吃掉对话框”的权重只能靠可复现性判断，不能还原当时事实。
- **模拟器与真机的差异**：模拟器为 AOSP Android 15，真机为 HyperOS Android 16；未在 Android 13/14 或非 MIUI ROM 上重复。

## 8. 可复现的下一步（约 10 分钟，任选其一）

复现配方（隔离包 + 真实选择器，端到端）：

```
# 1) 隔离构建（仓库外副本，避免覆盖 com.matrixflow.app）
cd D:\Dev_project\_rf10saf\matrixflow-native
D:\Dev_SDKs\Flutter_3.32.8\bin\flutter.bat build apk --release
# 2) 安装并推入无密钥合成备份
adb install build\app\outputs\flutter-apk\app-release.apk
adb push rf10saf-synthetic-backup.json /sdcard/Download/
# 3) 用命中区坐标点按，而不是用截图比例估算
adb shell uiautomator dump /sdcard/ui.xml && adb pull /sdcard/ui.xml
#    取 导出数据 (JSON) / 导入数据 (JSON) 的 bounds 中点再 input tap
# 4) 若要点出 A6 现象：对同一按钮在 1 秒内点两次，观察是否“对话框一闪即无”
```

若要继续追 A6：

1. **先排除命中问题**：以后所有设备点按都取 `uiautomator dump` 的 `bounds` 中点，并在点按后立刻 `logcat -c` 前先截图；一旦出现“无反应”，把当时的 `bounds` 与点按坐标一起记录。
2. **区分“点空”和“被屏障吃掉”**：点按后 300 ms 内截图；出现对话框再消失即为第二种；完全没有对话框即第一种。
3. **必须在插桩构建里验证日志**：本机 `Log.d` 不可见是 ROM 行为，若要靠日志判定“插件是否被调用”，需要临时在隔离副本里加 `debugPrint`（Release 需显式开启）或用 Debug/Profile 包，且不要用 A6 那种“日志为空”作为判据。
4. **人工确认 MIUI 选择器的两步式交互**：把“切到浏览 → Download → 滚动 → 选中 → 再按确定”写进人工清单，避免把“最近为空”误记成“选择器没出来”。

未实施、需要产品决策的候选改进（本包按约定不改，列出供后续包评估）：

- 导入/导出在等待选择器期间给出**可见进度反馈**（当前只有按钮禁用；DocumentsUI 冷启动实测约 4.8 s）。
- 凭据对话框是否保持 `barrierDismissible: true`。改成不可点外关闭，或在导出入口追加“取消导出”之外的回执，可以消除“第二次点按静默取消”的观感；这会改变现有交互语义，属产品决策。

## 9. 仓库与产物状态

- 仓库内**只新增本文件**。未改 `lib/`、`test/`、`android/`、`windows/`、`pubspec.yaml`、AGENTS/HANDOFF/CHANGELOG/返修计划，未与其它包并行修改 Store，未改提醒服务、保存协议与冻结的 React/Tauri/Capacitor。
- 隔离副本与产物在仓库外：`D:\Dev_project\_rf10saf\matrixflow-native`（改过身份字符串，**不入库**）、`_rf10saf-src.zip`、构建/测试日志、`exported-backup.json`（模拟器导出，751 B）、`device-exported-backup.json`（原机导出，755 B）、`ui*.xml` / `p*.xml` 语义树转储。语义树与截图只含无密钥合成数据。
- 设备侧遗留：原机上一阶段安装的 `com.matrixflow.rf10review` 未动；本轮 `com.matrixflow.rf10saf` 已卸载，推入/导出的两个文件已删除，`com.matrixflow.app` 与其自身备份文件均未改动。
- Windows 侧遗留：第一次 `Start-Process` 启动的 qemu 进程（PID 61112）处于 0 工作集的僵死状态，`taskkill`/`Stop-Process` 均返回“拒绝访问”，无法从本轮会话清理；它不占用 adb 端口（模拟器已 `adb emu kill` 关闭）。
