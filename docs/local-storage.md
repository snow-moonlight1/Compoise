# 本地存储

本文说明数据在设备里怎样保存。手动导出导入的 JSON 文件见[备份格式](backup-format.md)。

## 保存方式

- 任务库保存在 SharedPreferences 中。`SaveProtocol`（`lib/save_protocol.dart`）每次把完整快照写进两个槽中的一个，每个槽都带修订号和校验值，再更新提交指针指向这个槽。
- 启动时读取指针指向的槽。校验值用来发现数据损坏，但不能保证掉电时数据一定已经写到磁盘上。

| 快照中的键 | 内容 |
| --- | --- |
| `compoise-tasks` | 任务和子项 |
| `compoise-boards` | 任务板 |
| `compoise-schedule` | 日程 |
| `compoise-config` | AI 配置（不含密钥） |
| `compoise-settings` | 用户设置 |
| `compoise-active-board` | 当前任务板 ID |
| `compoise-has-seen-onboarding` | 是否看过新手引导 |

- 任务、任务板和日程总是在同一次提交里一起保存或一起回滚，不会只存下一半。
- API 密钥不进快照，通过 `lib/credential_store.dart` 存进系统安全存储：Android Keystore、Windows 系统凭据保护、Linux Secret Service。
- 一些只和本机有关的状态（例如日程引导是否看过、窗口位置）用单独的键保存，不进快照，也不随备份转移。导入备份不会改它们。

| 本机键（`lib/services/device_prefs.dart`） | 内容 |
| --- | --- |
| `compoise-update-check-enabled` | 是否自动检查更新，默认关闭 |
| `compoise-update-last-check` | 上次检查更新的时间（毫秒时间戳） |
| `compoise-ai-timeout-seconds` | 整理、拆分任务时等待 AI 的秒数：30、60 或 120，默认 60 |

- 诊断日志不在 SharedPreferences，而是应用支持目录下的 `logs/compoise.log`，每个文件最多约 256 KB，最多保留 3 个（`lib/diagnostics/app_log.dart`）。

## 同步数据

- 开启同步后，同步用的状态放在应用支持目录的 `sync/` 下，不在 SharedPreferences，不进快照，也不进 JSON 备份：`sync-meta.json`（设备 ID 和所在同步库）、`sync-state.json`（合并后的同步状态）、`sync-pending.json`（一轮同步写回任务库时短暂存在）、`sync-provider.json`（同步位置、WebDAV 地址和用户名或 OneDrive 账号名，不含密码和令牌）。
- 同步密码推导出的密钥（`compoise-sync-vault-key`）和 WebDAV 密码或 OneDrive 登录令牌（`compoise-sync-provider-secret`）和 API 密钥一样放在系统安全存储里。断开同步时删除。
- 同步结果写回任务库时走同一套快照提交，失败整体回滚。`sync/` 里的文件丢失或损坏不会丢任务，下一轮会以本机任务库为基线重新合并。详见[同步说明](sync.md#本机文件)。

## 启动恢复

- 提交槽或启动时读到的数据损坏（JSON 无效、ID 重复、时区无效、引用了不存在的对象等）时，应用进入恢复页面，原始数据保持不动。只有用户明确选择丢弃，才会清理这些数据。
- 实现见 `lib/storage.dart` 和 `lib/screens/startup_recovery_screen.dart`。

## 修改数据模型

1. 在 `lib/models.dart` 中给新字段定义默认值或可空语义，保证缺少这个字段的数据也能正常读出来。
2. 在 `lib/import_preflight.dart` 中更新字段白名单和校验。导入预检和 `DataMigrator` 的接受规则必须一致。
3. 补充测试：本地保存后重新打开、备份导出再导入、多卷恢复。只用合成数据。
4. 更新[备份格式](backup-format.md)。

运行时的临时状态不要放进快照。

> 发布之后，包名、存储键名和签名都不能再改。改了会让已安装的用户读不到原来的数据。

计次进度随任务一起进入双槽快照，备份格式为 v4。Linux 已送达提醒的触发时间保存在本机 `compoise-linux-delivered-reminders` 中，不进入备份；登录启动使用 XDG 配置目录的 `autostart/compoise.desktop`，默认不创建。
