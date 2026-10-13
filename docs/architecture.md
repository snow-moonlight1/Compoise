# 架构说明

方寸 · Compoise 是一个 Flutter 应用。Android、Windows 和 Linux 共用数据模型、状态管理、业务逻辑和绝大部分界面；通知、托盘、全局快捷键、文件选择等平台差异由平台服务承接。

## 分层

```text
界面（lib/screens、lib/widgets、lib/planner、lib/import_preview）
        │  只通过 Store 读写状态
        ▼
Store（lib/storage.dart）── 任务命令、查询、筛选、统计（lib/task_*.dart）
        │
        ├─ 本地保存（lib/save_protocol.dart，SharedPreferences）
        ├─ 系统安全存储（lib/credential_store.dart）
        ├─ 备份导出与导入（lib/backup_export.dart、lib/import_preflight.dart、lib/data_migrations.dart）
        └─ 平台服务（lib/services、lib/platform、lib/ocr）
```

## 主要模块

| 位置 | 作用 |
| --- | --- |
| `lib/main.dart` | 入口：创建提醒服务、持久化适配器和桌面外壳，再启动界面 |
| `lib/models.dart`、`lib/schedule_item.dart` | 任务、子项、任务板、日程、设置和 AI 配置等数据类型及序列化 |
| `lib/storage.dart` | `Store`：加载、保存、事务、撤销和全部用户操作；页面不各自实现业务规则 |
| `lib/task_commands.dart`、`task_query.dart`、`task_filter.dart`、`task_stats.dart` | 任务的修改、读取、筛选和统计 |
| `lib/planned_policy.dart`、`lib/deadline_policy.dart`、`lib/calendar_dates.dart` | 计划日、截止日期和紧急性规则，见[任务与日程](tasks-and-schedule.md) |
| `lib/planner/` | 日程页：日视图、周视图、任务池、日程编辑 |
| `lib/screens/` | 页面：四象限首页、今天、已完成、搜索、设置、引导、启动恢复 |
| `lib/widgets/` | 可复用组件：任务卡片、详情面板、输入面板等 |
| `lib/screenshot_import/`、`lib/import_preview/`、`lib/ocr/` | 截图识别：选图、OCR、整理成草稿、校对页，见[截图识别导入](ocr.md) |
| `lib/ai_service.dart`、`ai_presets.dart`、`ai_capabilities.dart`、`model_discovery.dart` | AI 请求、服务商预设、模型能力和模型列表，见 [AI 服务商](ai-providers.md) |
| `lib/services/` | 提醒、Windows 桌面外壳（托盘、单实例、全局快捷键）、窗口位置、Linux 测试通知 |
| `lib/platform/` | 设备时区 |
| `lib/ui/` | 平台交互策略（`platform_ui_policy.dart`）、动画策略、字体策略 |
| `lib/theme.dart` | 主题，包括漫画描边和拟态两种可选风格 |
| `lib/l10n.dart` | English、简体中文、日本語文案 |
| `lib/experiments/` | 尚未接入正式应用的实验（网盘同步、开发模式、托管 AI、拟态组件样板），正式界面不引用它们 |
| `native/ocr/` | OCR 原生库（C++，ncnn + PP-OCRv5），通过 FFI 调用 |

## 数据

- 任务板、任务、子项、日程和普通设置保存在本机 SharedPreferences，用双槽快照原子提交，详见[本地存储](local-storage.md)。
- API 密钥通过 `flutter_secure_storage` 保存在系统安全存储中。
- 没有账号，也没有自动云同步。用户可以用 JSON 文件备份和转移数据，详见[备份格式](backup-format.md)。

## 平台

| 平台 | 说明 |
| --- | --- |
| Android | `applicationId` 和命名空间都是 `com.compoise.app`。提醒使用通知和闹钟调度，开机后恢复。截图通过系统文件选择器（SAF）读取。 |
| Windows | runner 承接托盘、单实例、全局快捷键、关闭到托盘和窗口生命周期。数据目录为 `%APPDATA%\Compoise\Compoise`。 |
| Linux | GTK 窗口，密钥通过 Secret Service 保存，文件选择依赖 zenity 或 kdialog。设置里可以发送测试通知，但还没有按时投递的提醒，也没有托盘和全局快捷键。 |

手机和桌面的交互差异（悬停、右键、双击、拖放、快捷键、侧边任务池等）由 `lib/ui/platform_ui_policy.dart` 决定，判断依据是平台，而不是窗口宽度。

## 测试

- `test/`：单元测试和组件测试，`flutter test` 全部运行。
- `integration_test/`：集成测试，CI 在 Linux 和 Windows 上用模拟数据运行。
- `test/fixtures/`：测试数据，包括真实截图和 OCR 评测样本（`test/fixtures/ocr-evaluation/`）。

命令见[开发指南](development.md)。
