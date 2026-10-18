# 提醒

提醒由任务或子项的提醒时间决定。截止日期只影响紧急性，不会触发通知。编辑、完成或删除任务时，提醒服务会按 Store 的最新状态更新相应的通知。

## 调度

- `ReminderService`（`lib/services/reminder_service.dart`）负责权限检查、安排和取消通知、启动时恢复，以及记录失败。
- 提醒用任务和子项的固定 ID 关联。点击通知后，应用打开对应的任务。
- 已完成、已删除或提醒时间已更改的任务，会清理掉旧的调度。暂时失败的调度会保留下来，之后重试或提示用户。

## 各平台

| 平台 | 行为 |
| --- | --- |
| Android | 使用通知、精确闹钟和开机恢复。首次完成引导后提供可跳过的提醒设置，依次申请通知、准时提醒和后台运行（忽略电池优化，`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`），并提供厂商自启动入口，见[任务与日程 · Android 提醒设置](tasks-and-schedule.md#android-提醒设置)。实际的准时程度取决于系统版本、权限和厂商的省电策略。 |
| Windows | 使用本地通知，配合托盘和应用生命周期。 |
| Linux | 应用运行时用定时器向桌面通知服务投递，关闭到托盘后继续生效；完全退出期间不能投递。启动时汇总尚未送达的过期提醒，同一触发时间只汇总一次。设置里可选择登录时启动（默认关闭）。GNOME 等桌面可能需要托盘扩展。 |

## 限制

系统可能延迟或拦截后台通知。用户需要在系统设置里允许通知，并按提示允许后台运行或闹钟权限。强制停止、厂商省电限制、撤回权限或重启设备都可能影响送达，应用不能保证每条提醒都准时。

## 相关代码和测试

- `lib/services/reminder_service.dart`：调度、权限、记录和恢复。
- `lib/screens/android_reminder_setup_screen.dart`、`android/app/src/main/kotlin/com/compoise/app/ReminderSettingsBridge.kt`：Android 提醒设置页，以及读取通知、精确闹钟、电池优化和厂商自启动状态的原生接口。
- `lib/storage.dart`：任务变化与提醒状态的协调。
- `lib/screens/settings_screen.dart`：权限说明、测试通知、“提醒与后台设置”入口和问题提示。
- `test/reminder_service_test.dart`、`test/android_reminder_setup_test.dart` 等提醒相关测试。

## 排查

调度、权限探测和取消失败时，`ReminderService` 会把失败类型写进本机诊断日志（`lib/diagnostics/app_log.dart`），只记录错误类型和提醒编号，不记录任务标题。用户可以在“设置 → 帮助与关于 → 导出诊断信息”导出，附在问题报告里。
