# 本地数据与兼容性

本文只说明**设备内的保存与演进**。手动交换的 JSON 文件、导入限制和多卷恢复以 [备份格式](BACKUP_FORMAT.md) 为准。

## 本地保存

Android 与 Windows 的任务库使用 SharedPreferences。`SaveProtocol` 把一个完整快照写入两个带 revision 和校验值的槽，再用提交指针指定有效槽；启动优先读取已提交槽。旧键继续作为兼容镜像，不能把单个镜像键当成最新提交。校验用于发现损坏，不保证设备掉电后的物理持久性。

| 快照中的键 | 内容 |
|---|---|
| `matrixflow-tasks` | 任务及嵌套子项 JSON |
| `matrixflow-boards` | 任务板 JSON |
| `matrixflow-config` | 非敏感 AI 配置 JSON；API 密钥另存于系统保护存储 |
| `matrixflow-settings` | 用户设置 JSON |
| `matrixflow-active-board` | 当前任务板 ID |
| `matrixflow-has-seen-onboarding` | 引导完成状态 |

提交槽或启动数据损坏时，应用进入恢复流程，避免直接覆盖原始内容。旧版本明文密钥迁移时，须先写入并读回系统凭据存储，再清理本地槽与镜像；失败则保留可重试状态。Android 系统自动备份与设备转移不能作为密钥恢复方案。相关实现见 [save_protocol.dart](../lib/save_protocol.dart)、[storage.dart](../lib/storage.dart) 和 [credential_store.dart](../lib/credential_store.dart)。

## 变更数据模型时

1. 在 [models.dart](../lib/models.dart) 为新字段定义读取默认值或可空语义，并明确 v1 降级写出是否剔除。旧库和旧备份缺少字段时应能读取。
2. 更新 [import_preflight.dart](../lib/import_preflight.dart) 的字段白名单和必要校验；导入预检与 `DataMigrator` 不能出现互相矛盾的接受规则。
3. 确认本地保存、v2 备份往返和 v1 有损导出的预期行为；用合成数据验证。若改变用户可见的文件契约，更新 [备份格式](BACKUP_FORMAT.md)。

本地运行时临时状态不要加入保存快照。字段的实际默认值、版本行为和兼容边界由模型、预检与相关测试共同约束。
