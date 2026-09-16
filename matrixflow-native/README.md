# MatrixFlow AI Native 客户端 (Flutter)

[![Flutter Tests](https://img.shields.io/badge/Flutter%20Tests-255%2F255%20Passed-brightgreen)](test/)
[![Analyze](https://img.shields.io/badge/Analyze-0%20Issues-brightgreen)](lib/)
[![Platforms](https://img.shields.io/badge/Platforms-Android%20%7C%20Windows-blue)]()

`matrixflow-native/` 是 MatrixFlow AI 的官方跨平台自绘引擎客户端。基于 Flutter 3 与 Material 3 构建，**不依赖任何 WebView**，一套 Dart 源码提供高帧率渲染、触控手势反馈以及深度系统集成，无缝运行于 **Android (Phone/Tablet)** 与 **Windows (Desktop)**。

---

## 🏗️ 架构与模块组织

```
lib/
├── main.dart                    # 应用根入口：多 Provider 状态接线与三语 Locale 响应
├── models.dart                  # 领域数据模型 (Task, SubTask, Board, AppSettings, AIConfig, ExportData)
├── storage.dart                 # 全局状态中心 (Store: ChangeNotifier) 与 SharedPreferences 本地持久化
├── theme.dart                   # Material 3 动态配色与 CombinedTextScaler 复合字号缩放器
├── l10n.dart                    # 中英日三语国际化字典 (zh-CN / en / ja)
├── data_migrations.dart         # WP11 数据迁移门禁 (v1/v2 兼容读取、安全剥离与孤儿任务防护)
├── task_stats.dart              # WP27 纯函数统计与 7 日完成趋势直方图计算模型
├── deadline_policy.dart         # WP22 本地时区日历天截止策略与紧急性流转算法
├── ai_presets.dart              # WP01 官方 AI 服务商预设与端点注册表
├── ai_service.dart              # OpenAI / OpenAI Responses / Anthropic 三协议直连客户端
├── shortcuts.dart               # WP26 键盘快捷键与 MatrixFlow Intent 系统
├── screens/
│   ├── matrix_screen.dart       # 十字四象限主界面、双视图切换、快捷新建与批量操作
│   ├── settings_screen.dart     # AI 服务商配置、字体显示、托盘开关、备份导入导出
│   ├── search_screen.dart       # 本地中英日全文与子项关键词多维组合筛选
│   ├── completed_screen.dart    # 已完成任务集中复盘、7 日趋势图与就地恢复
│   └── onboarding_screen.dart   # 新手 5 步响应式引导与手势说明教程
├── services/
│   ├── reminder_service.dart    # 跨平台本地通知调度器 (Android AlarmManager & WinRT Toast)
│   └── desktop_shell_service.dart # Windows 托盘生命周期、关闭到托盘与主窗口控制
└── widgets/
    ├── task_card.dart           # 任务卡片 (首行复选框、逐行删除线、长按拖拽、滑动操作)
    ├── quadrant_pane.dart       # 极简无框十字象限面板
    ├── task_detail_panel.dart   # 任务详情侧边栏/抽屉 (父子任务多行编辑、截止日期选择、AI 拆解)
    ├── command_palette.dart     # Ctrl+K 全局快速命令面板
    ├── task_list_view.dart      # 宫格/列表视图切换
    ├── task_stats_bar.dart      # 响应式流式进度统计条
    └── input_sheet.dart         # 换行快速批量添加与 AI 交互面板
```

---

## 🧪 自动化测试套件 (255/255 Passed)

项目具备完善的自动化测试基线，涵盖数据模型、状态演进、多端交互与平台适配：

| 测试文件 | 用例数 | 覆盖范围 |
|---|---|---|
| `test/models_test.dart` | 42 | 数据模型构造、JSON 序列化、字段默认兜底 |
| `test/data_migration_test.dart` | 24 | WP11 数据版本演进、v1/v2 导入导出往返兼容 |
| `test/task_stats_test.dart` | 26 | 进度统计、7 日完成直方图日历天聚合、父子独立防重 |
| `test/task_query_test.dart` | 18 | 中英日关键词全文搜索、日历跨度组合过滤 |
| `test/deadline_policy_test.dart` | 15 | 截止日期日历天计算、Q2→Q1/Q4→Q3 自动升级策略 |
| `test/reminder_service_test.dart` | 14 | 本地通知调度、31 位 FNV-1a 哈希、过期抑制 |
| `test/windows_reminder_test.dart` | 4 | Windows WinRT 通知绑定与托盘定时器保活 |
| `test/shortcuts_command_palette_test.dart` | 12 | Ctrl+K 唤起、命令过滤、输入法焦点防冲突 |
| `test/desktop_shell_test.dart` | 8 | 桌面服务生命周期、非桌面平台安全 no-op |
| `test/onboarding_test.dart` | 5 | 新手引导 5 页流转、首启标记持久化与重置 |
| `test/widget_regression_test.dart` | 87 | 十字矩阵渲染、手势滑动撤销、详情面板脏检查、三语切换全量 UI 回归 |

---

## 🛠️ 本地命令与验证

所有构建与验证命令均在 `matrixflow-native/` 目录下执行：

```bash
# 静态分析（确保 0 issues）
flutter analyze --no-pub

# 运行全量单元与组件回归测试（确保 255/255 passed）
flutter test --no-pub

# 本地调试启动
flutter run

# 构建 Android Release APK
flutter build apk --release --no-pub

# 构建 Windows Release 原生桌面程序
flutter build windows --release --no-pub
```

构建生成的双端产物支持使用根目录的自动化打包脚本 `scripts/build_release.ps1` 进行一键归档与校验和生成。
