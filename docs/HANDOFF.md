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
| Windows release | 用户装好 C++ 工具链后重试成功，`matrixflow-native/build/windows/x64/runner/Release/`；运行/分发需要整个目录，不能只拷贝 exe |
| Android release | 未通过，见下文 B01 |
| Android 实机 E2E | 本轮未执行；默认 flutter test 不包括 integration_test |

首批新增 7 个回归用例在原代码上全部失败，修复后通过。输入选择器已改为稳定 key，供下轮设备集成测试使用。

## 剩余范围与用户偏好

用户最新指示：额度有限，先归纳全部已发现 Bug、评估剩余工作量；只顺手处理小问题，大范围继续修改前先交报告。**本轮应用层修复已收敛，不应重新无界审查或重做已修复功能。**

### B01：唯一已确认的剩余构建阻塞

`flutter build apk --release --no-pub` 两次失败，顺序重跑仍报：

`GeneratedPluginRegistrant.java` 引用 `dev.flutter.plugins.integration_test.IntegrationTestPlugin`，但 release Java 编译找不到该包。

本机 Flutter 是 `3.31.0-1.0.pre.88 / Dart 3.8.0 开发版`。integration_test 正确位于 dev_dependencies。需要进一步定位生成注册与 Gradle 排除 dev 插件的不一致。预估中等工作量 30–90 分钟；暂未改全局 SDK、未把测试依赖放入生产 dependencies、未手改生成注册文件。

### 后续验收

按报告 B03 在 Android 实机复测键盘、返回、拖拽、文件选择器、AI 取消和三语日期。构建成功不等于实机验收完成。Windows 工具链阻塞已经关闭，不要重复报告缺少 Visual Studio。

正式签名/图标、存储逐版迁移与跨键事务仍是既有后续工作，不属于本轮继续扩改范围。

## 下一轮启动提示词

接手 MatrixFlow AI（纯本地四象限待办，Web + Flutter Android/Windows 双端）。先读 AGENTS.md、docs/NATIVE_BUG_REVIEW_2026-09-07.md 的 B01 和本交接。上一轮 29 类修复已完成并收尾提交，64 项测试和静态分析通过，Android debug 与 Windows release 构建成功；Windows C++ 工具链已经可用。

本轮唯一开发目标：**定位并尝试解决 B01：Android release 编译时 GeneratedPluginRegistrant 引用了找不到的 integration_test 插件。用户已授权必要的最小修复，不要停留在方案或再次请求执行许可。** 优先核实事实、选择工程范围内可复现的处理方式，再验证 release 构建。额度优先，不重复全工程审查或扩展到其他特性。

建议顺序：

1. `git status` / `git log -1` 确认接手基线；读取 `matrixflow-native/pubspec.yaml`、`android/app/build.gradle.kts`、`android/settings.gradle.kts` 和本地 `docs/native-release-build-final.log`（日志被 Git 忽略，缺失时重新复现）。
2. 定位 Flutter 插件发现/注册与 Gradle dev_dependency 过滤的不一致。已查看过 SDK 的 `packages/flutter_tools/lib/src/flutter_plugins.dart` 中 `findPlugins` / `injectPlugins(releaseMode)`、`lib/src/project.dart`、`gradle/src/main/groovy/flutter.groovy`；它们是排查线索，尚未证明最终根因。两次 release 失败，第二次已顺序单独构建。
3. 尝试最小修复并解释依据；不手改自动生成注册文件，不把 integration_test 搬进生产 dependencies 来掩盖错误，不直接修改全局 SDK。若证据指向需更换 SDK，先明确版本兼容影响和项目隔离方案。
4. 同一工程的 Flutter 构建/测试顺序运行，避免生成文件互相覆盖。先验证 Android release；若改代码/依赖，跑 `flutter test` 和 `flutter analyze`，需要时验证 debug。不要无故重复 Windows 构建。
5. 更新报告 B01、CHANGELOG 和本交接。只有实际 release 构建通过才关闭 B01；若无法解决，记录已尝试方式、真实错误和下一步，保留现有成果。

环境：Flutter SDK `D:\Dev_SDKs\Flutter_SDK`，Android SDK `D:\Dev_SDKs\Android_studio_SDK`，JDK `D:\Dev_SDKs\jdk-21.0.12.1+1`。构建仍使用既有 debug 签名，正式签名不在本轮任务内。

## 收尾与工作区

- 会话最初工作区干净，无 pre-existing 用户改动；仅显式暂存本轮原生代码、回归测试和受影响文档。
- 本次 closeout 只更新交接任务及提交状态，没有继续修 B01，没有删除文件，没有重跑已经通过且代码未改变的测试。
- 重要文件：`lib/storage.dart`、`lib/ai_service.dart`、`lib/widgets/input_sheet.dart`、`lib/screens/`、三份新增 `test/*regression_test.dart` 及审查报告。
- APK、Windows Release 整目录及 `docs/native-*.log` 属于本地产物/忽略文件，不提交。它们保留用于复测与排查，不是删除候选。
