# 架构说明

方寸 · Compoise 是一个 Flutter 应用。Android、Windows 与 Linux 预览版共用任务模型、状态管理、业务操作和大部分界面；操作系统通知、Windows 托盘/快捷键等差异由平台服务承接。

## 应用组成

- lib/main.dart 是组合入口，创建提醒服务、持久化适配器和 Windows 单实例服务，再构建 Flutter 界面。
- lib/models.dart 定义任务、子任务、任务板、AI 配置和应用设置等数据类型。
- lib/storage.dart 中的 Store 管理应用状态，负责加载、保存、迁移和用户操作。页面通过 Store 读写状态，避免在各组件内重复实现业务规则。
- lib/task_commands.dart、lib/task_query.dart、lib/task_filter.dart 和 lib/task_stats.dart 分别承接任务变更、读取、筛选和统计逻辑。
- lib/screens/ 组织页面流程；lib/widgets/ 提供可复用交互组件。
- lib/l10n.dart 提供 English、简体中文和日本語文案。

## 数据与 AI

任务板、任务、子任务和普通设置保存在设备本地的 SharedPreferences。API 密钥通过 flutter_secure_storage 存入平台提供的安全凭据存储。应用没有账号或自动云同步。

文件备份的导出、预检与恢复分别由 `backup_export.dart`、`import_preflight.dart` 和 Store 承接。文件契约见 [备份格式](BACKUP_FORMAT.md)；设备内的提交槽见 [本地数据与兼容性](DATA_COMPATIBILITY.md)。

AI 层由预设、模型能力判断、模型发现和请求协议适配组成。支持 OpenAI Compatible、OpenAI Responses 和 Anthropic Messages。密钥由用户提供；调用时相关任务文本会发送到用户配置的服务端点。普通任务管理不依赖 AI。

## 平台服务

- Android 使用 applicationId com.matrixflow.app 作为已存在的安装身份；显示名称和桌面图标是独立资源。品牌名称按 Android 系统语言资源切换。
- Windows runner 承接托盘、单实例、全局快捷键、关闭到托盘和窗口生命周期。用户可见窗口标题与当前应用语言同步。
- Linux runner 提供 GTK 桌面窗口；密钥通过 Secret Service 保存。Linux 当前使用无通知的提醒服务，也没有托盘、全局快捷键或关闭到托盘。
- Android 和 Windows 的提醒逻辑统一在 Flutter 服务中，平台插件负责通知投递、权限和系统调度。提醒送达受系统权限和设备策略影响。

常规回归测试位于 `test/`，集成测试位于 `integration_test/`；命令和构建步骤见 [开发指南](DEVELOPMENT.md)。安装升级、通知授权和系统后台行为仍需在目标设备检查。
