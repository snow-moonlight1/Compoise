# MatrixFlow AI — Native（Flutter 跨平台版）

MatrixFlow AI 的原生渲染版本：**不经过 WebView**，用 Flutter（Impeller/Skia 自绘引擎）实现丝滑动画，一套 Dart 代码同时产出 **Android APK** 与 **Windows 桌面应用**。Web 版（React 19 + Vite 6）见 [Web 版](../README.md)。

## 功能

- 艾森豪威尔四象限矩阵：任务卡拖拽换象限（带目标高亮与拖拽反馈）、一键清空
- AI 智能分类：头脑风暴批量输入 → 判定象限 + 理由 + 同类合并（分组确认弹窗）
- AI 长期任务拆解：单任务即时拆解 + 批量拆解审查面板
- 三协议 AI 调用（与 Web 版一致）：**OpenAI Compatible / OpenAI Responses / Anthropic Messages**，统一「地址 + 模型名 + 密钥」三要素，30 秒超时，按协议测试连接
- 任务卡：完成划线动画、AI 理由展示、子任务（增删改查）、截止日期（本地时区、逾期/今日/剩余天数着色）、长期标记
- 截止日期自动升级：Q2→Q1、Q4→Q3（阈值可调，每小时检查）
- 多任务板、隐藏已完成、批量选择编组、父任务自动完成
- 数据备份：JSON 导入导出，**与 Web 版备份格式互通**（ExportData v1，合并模式自动去重）
- 三语界面（EN / 中文 / 日本語）· 亮暗主题 × 5 种强调色（Material 3 动态取色）

## 开发

前置：Flutter SDK、Android SDK（`flutter config --android-sdk <path>`）、Windows 桌面构建另需 VS「使用 C++ 的桌面开发」工作负载。

```bash
flutter pub get
flutter analyze              # 0 issues
flutter test                 # 64 项单元/Widget 测试：模型 / AI / 存储 / 交互回归
flutter run                  # 开发运行（选设备）
```

## 构建

```bash
flutter build apk --debug     # Android → build/app/outputs/flutter-apk/app-debug.apk
flutter build windows         # Windows → build/windows/x64/runner/{Debug,Release}/
flutter test integration_test/app_test.dart -d <device>   # 端到端（内置 mock AI 服务器）
```

## 架构

```
lib/
  main.dart            入口：Provider + 主题/语言接线
  models.dart          与 Web 版 types.ts 同构的数据模型（ExportData 兼容）
  quadrant.dart        象限常量与颜色（含 "Q1" 字符串容错解析）
  storage.dart         唯一状态中心（ChangeNotifier）+ SharedPreferences 持久化
                       （键与 Web 版相同：matrixflow-tasks/boards/config/settings）
  ai_service.dart      三协议 HTTP 客户端 + JSON 多级兜底解析 + 测试连接
  l10n.dart            三语字典（与 Web 版 translations.ts 同源）
  theme.dart           Material 3 主题（明暗 × 5 种子色）
  screens/             矩阵主页、设置页
  widgets/             任务卡、象限面板、输入面板、入场/划线动画组件
```

## 已知差异（相对 Web 版）

2026-09-07 深度审查修复及剩余问题见 [Bug 探查报告](../docs/NATIVE_BUG_REVIEW_2026-09-07.md)。当前 Android debug、Windows release 构建通过；Android release 存在 integration_test 自动注册错误，尚不可视为已验证发布包。

- 导入预览为「合并 / 覆盖」两步确认，暂无逐字段勾选
- 桌面端窗口尺寸调整与托盘等深度集成未做
- 首次启动到首帧在低端机上有 1-2 秒引擎初始化（原生引擎预热，非 WebView）
