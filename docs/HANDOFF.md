# 项目交接文档（HANDOFF.md）

最后更新：2026-09-07。本轮审查基线：`e3856349f11fd06a44bff053c05406facc9c9e8b`。本轮修复与交接一并纳入收尾提交 `fix(native): 修复原生端交互与数据缺陷并交接B01`；接手时以 `git log -1` 核对实际提交。

## 当前交付

已先阅读全部项目 docs，再走查 Flutter 原生端的全部原有 Dart 文件及平台关键配置，集中处理 29 类已确认问题。完整问题、触发路径、修复位置、验证边界见 [Flutter 原生端 Bug 探查报告](NATIVE_BUG_REVIEW_2026-09-07.md)。

- 数据：启动损坏记录容错、导入预校验和批内去重、编组保留原子项、父子完成同步、活动板恢复、唯一 id、截止日期及时检查、写入异常提示。
- 交互：键盘与安全区、窄屏布局、长按拖拽、批量选择和返回、路由控制器释放、单/批拆解生命周期、连续 AI 提交与原任务板绑定。
- AI/平台：总超时和取消、异常结果保留输入、分组与拆解区分、Anthropic 地址、JSON 对象提示、Material 三语本地化、Android 导出和联网权限。
- 保留纯本地设计及 ExportData v1。未修改 Web 应用逻辑，未使用真实 AI 密钥或读取真实备份。

## 已验证

| 检查 | 结果 |
|---|---|
| `flutter test --no-pub --reporter expanded` | 64/64 通过，含原有 20 项与新增 44 项 |
| `flutter analyze --no-pub` | 0 issues |
| Android debug | 构建成功，`matrixflow-native/build/app/outputs/flutter-apk/app-debug.apk` |
| Windows release | 构建成功，`matrixflow-native/build/windows/x64/runner/Release/`；运行/分发需要整个目录，不能只拷贝 exe |
| Android release | **构建成功**，`matrixflow-native/build/app/outputs/flutter-apk/app-release.apk`（22.8MB），B01 已关闭 |
| Android 实机 E2E | 本轮未执行；默认 flutter test 不包括 integration_test |

首批新增 7 个回归用例在原代码上全部失败，修复后通过。输入选择器已改为稳定 key，供下轮设备集成测试使用。

## 剩余范围与用户偏好

用户最新指示：额度有限，先归纳全部已发现 Bug、评估剩余工作量；只顺手处理小问题，大范围继续修改前先交报告。**本轮应用层修复已收敛，构建阻塞项已全部清零。**

### B01：构建阻塞（已解决并关闭）

- **现象**：`flutter build apk --release --no-pub` 失败，报 `GeneratedPluginRegistrant.java: 错误: 程序包dev.flutter.plugins.integration_test不存在`。
- **根因**：Flutter CLI 在传入 `--no-pub` 时受 `regeneratePlatformSpecificToolingIfApplicable` 内 `if (!shouldRunPub) return;` 保护，跳过了按 release 构型重生成平台插件文件；此前 `pub get` 或 `flutter test` 在 debug 模式下写入的 `GeneratedPluginRegistrant.java` 保留了 `dev_dependencies` 中的 `integration_test` 插件注册，而 Gradle 的 `flutter.groovy` 在 release 构建中剥离了测试依赖，javac 编译找不到该类。
- **方案**：在 `matrixflow-native/android/app/build.gradle.kts` 添加 Gradle 任务 `cleanDevPluginsFromReleaseRegistrant`，在 `preReleaseBuild` 与 `compileReleaseJavaWithJavac` 前自动剥离残留在生成文件中的测试插件注册。不手改生成文件，不修改生产 dependencies，不改动全局 SDK。
- **验证**：`flutter build apk --release` 与 `flutter build apk --release --no-pub` 均顺序构建成功，产出 22.8MB APK；64/64 测试全过，`flutter analyze` 0 警告，Android debug 构建通过。

### 后续验收

按报告 B03 在 Android 实机复测键盘、返回、拖拽、文件选择器、AI 取消和三语日期。构建成功不等于实机验收完成。Windows 工具链阻塞已经关闭，不要重复报告缺少 Visual Studio。

正式签名/图标、存储逐版迁移与跨键事务仍是既有后续工作，不属于本轮继续扩改范围。

## 下一轮启动提示词

接手 MatrixFlow AI（纯本地四象限待办，Web + Flutter Android/Windows 双端）。先读 AGENTS.md、docs/NATIVE_BUG_REVIEW_2026-09-07.md 和本交接。上一轮 29 类交互/数据修复已完成，B01（Android release 编译）与 B02（Windows 工具链）已全部解决关闭。当前 64 项测试与静态分析通过，Android debug/release 及 Windows release 构建全部成功。

下一轮核心目标：**按 B03 进行 Android 实机交互与端到端复测（键盘避让、跨象限拖拽、批量选择、系统文件选择器、AI 取消/重试等）**，或根据用户需求推进正式签名/图标或存储迁移。保持纯前端 + 本地存储设计前提，不引入后端。

## 收尾与工作区

- 会话最初工作区干净，无 pre-existing 用户改动；仅显式暂存本轮原生代码、回归测试和受影响文档。
- 本次 closeout 只更新交接任务及提交状态，没有继续修 B01，没有删除文件，没有重跑已经通过且代码未改变的测试。
- 重要文件：`lib/storage.dart`、`lib/ai_service.dart`、`lib/widgets/input_sheet.dart`、`lib/screens/`、三份新增 `test/*regression_test.dart` 及审查报告。
- APK、Windows Release 整目录及 `docs/native-*.log` 属于本地产物/忽略文件，不提交。它们保留用于复测与排查，不是删除候选。
