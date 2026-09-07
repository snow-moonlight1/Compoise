# 项目交接文档（HANDOFF.md）

最后更新：2026-09-07 16:10 | 当前基线 Commit：`378003d`

---

## 1. 项目全貌与当前状态

MatrixFlow AI 是 AI 驱动的艾森豪威尔矩阵任务管理应用，当前为**双轨架构**，共享同一套数据备份模型（`ExportData` v1）与 AI 三协议：
- **Web / 混合端**：React 19 + Vite 6 + Tailwind CSS + Tauri v2 / Capacitor，产物体积已优化至 288.5 KB（gzip 87 KB），`npm run build` + `npx tsc --noEmit` 通过。
- **原生跨平台端（`matrixflow-native/`）**：Flutter 3 + Dart，Impeller / Skia 自绘引擎，无需 WebView，直接编译为 Android APK 与 Windows 原生桌面应用。20 项自动化测试（`flutter test`）与静态分析（`flutter analyze`）已全量通过。

---

## 2. 本轮已完成工作（2026-09-07）

1. **Matrix Native 正式纳入主仓库**：
   - 移除了 `matrixflow-native` 内部的独立临时 `.git`，将 53 个源代码与配置文件通过主仓库 Git 统一纳管（`378003d`），工作区保持 clean。
2. **全量文档体系核验与对齐（Neat Freak）**：
   - `README.md`：更新双轨架构、快速开始、构建命令及文档全索引。
   - `AGENTS.md`：更新 Monorepo 定位、双端验证命令及 App.tsx 实际行数（1672 行）。
   - `docs/ARCHITECTURE.md`：修正三协议架构、更新体积（288 KB）并移除已解决的 Rollup 警告，记录 Web 与 Native 同构数据模型。
   - `docs/DEVELOPMENT.md`：补充 Flutter 命令、本机 SDK 路径说明、修正 subst 盘符路径。
   - `matrixflow-native/README.md`：修复失效相对路径。
   - `docs/CHANGELOG.md`：在顶部追加 2026-09-07 原生跨平台版集成与文档体系全量对齐记录。

---

## 3. 当前焦点与待解决问题（Backlog）

### 🚨 核心痛点：Android 原生实机体验有待打磨
- **用户实测反馈**：用户在 Android 真实设备上运行了 `matrixflow-native`，反馈整体可用但**交互、布局与体验细节上的问题较多**（未逐一详述，需 Agent 主动做第一轮静态审查与缺陷收敛）。
- **定位范围**：`matrixflow-native/lib/`（主要是 `widgets/`、`screens/` 与 `ai_service.dart`）。

---

## 4. 下一轮 Agent 接手指南

下一轮主要任务：**对 `matrixflow-native` 进行深入的 Android 体验与 Bug 专项排查，主动修复第一批问题并交付自查清单，供用户二次实机复测。**

### 审查与排查维度
1. **键盘遮挡与 Inset 适配**：
   - `widgets/input_sheet.dart` 和编辑弹层在软键盘弹起时是否被遮挡，检查 `resizeToAvoidBottomInset`、`MediaQuery.viewInsets` 及 `SingleChildScrollView`。
2. **触屏手势与滚动冲突**：
   - 四象限列表（`quadrant_pane.dart`）中的拖拽（`Draggable` / `LongPressDraggable`）与上下滑动是否打架，移动端小屏拖拽放置区域边界。
3. **安全区与 Android 返回键**：
   - 检查顶部状态栏、底部手势导航条是否使用了 `SafeArea` 防遮挡；
   - 检查弹窗和 Sheet 是否适配现代 Android 返回导航（推荐 `PopScope` 而非过期的 `WillPopScope`）。
4. **异步生命周期安全（Mounted Check）**：
   - 检查 `screens/` 与 `widgets/` 中所有 `await` 异步调用之后，访问 `context` 或调用 `setState` 前是否加入了 `if (!mounted) return;` 保护。
5. **AI 异常捕获与用户提示**：
   - `ai_service.dart` 网络超时、未配置 key、服务商 4xx/5xx 报错或非法 JSON 时，杜绝出现底层异常红屏，确保通过友好 SnackBar 告知。
6. **文字截断与排版**：
   - `task_card.dart`、象限标签在小屏或多语（中/英/日）长文本下的 RenderFlex overflow 风险。

### 必跑门禁
```bash
# 原生端静态检查（必须 0 警告）
& "D:\Dev_SDKs\Flutter_SDK\bin\flutter.bat" analyze

# 原生端测试（必须全部通过）
& "D:\Dev_SDKs\Flutter_SDK\bin\flutter.bat" test
```

---

## 5. 下一轮启动提示词（可以直接发送给下一轮 Agent）

```markdown
/fable-mode 请阅读 docs/HANDOFF.md 并接管 MatrixFlow AI 项目。

当前任务：对工程中的 Flutter Android 原生端（`matrixflow-native/`）进行一轮系统性的 Bug 审查与集中修复。
用户实机测试反馈细节问题较多，请按照 docs/HANDOFF.md 第 4 节列出的 6 个核心维度（键盘遮挡、手势冲突、安全区与PopScope、异步mounted生命周期、AI异常友好反馈、文字截断），主动走查代码并就地修复第一批问题。

修复后请运行：
1. & "D:\Dev_SDKs\Flutter_SDK\bin\flutter.bat" analyze （保持 0 issues）
2. & "D:\Dev_SDKs\Flutter_SDK\bin\flutter.bat" test （保持全部测试通过）

最后输出已修复的问题清单与建议用户真机复测的要点。
```
