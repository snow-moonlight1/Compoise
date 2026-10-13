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
- 一些只和本机有关的状态（例如日程引导是否看过、窗口位置）用单独的键保存，不进快照，也不随备份转移。

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
