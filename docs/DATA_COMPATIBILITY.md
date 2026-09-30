# 本地数据与兼容性

本文只说明**设备内的保存与演进**。手动交换的 JSON 文件、导入限制和多卷恢复以 [备份格式](BACKUP_FORMAT.md) 为准。

## 本地保存

Android、Windows 与 Linux 预览版的任务库使用 SharedPreferences。`SaveProtocol` 把一个完整快照写入两个带 revision 和校验值的槽，再用提交指针指定有效槽；启动优先读取已提交槽。旧键继续作为兼容镜像，不能把单个镜像键当成最新提交。校验用于发现损坏，不保证设备掉电后的物理持久性。

| 快照中的键 | 内容 |
|---|---|
| `matrixflow-tasks` | 任务及嵌套子项 JSON |
| `matrixflow-boards` | 任务板 JSON |
| `matrixflow-schedule` | 日程记录 JSON 数组，与任务/板同批提交与恢复 |
| `matrixflow-config` | 非敏感 AI 配置 JSON；API 密钥另存于系统保护存储 |
| `matrixflow-settings` | 用户设置 JSON |
| `matrixflow-active-board` | 当前任务板 ID |
| `matrixflow-has-seen-onboarding` | 引导完成状态 |

提交槽或启动数据损坏时，应用进入恢复流程，避免直接覆盖原始内容。旧版本明文密钥迁移时，须先写入并读回系统凭据存储，再清理本地槽与镜像；失败则保留可重试状态。Android 系统自动备份与设备转移不能作为密钥恢复方案。相关实现见 [save_protocol.dart](../lib/save_protocol.dart)、[storage.dart](../lib/storage.dart) 和 [credential_store.dart](../lib/credential_store.dart)。

旧提交槽缺少 `matrixflow-schedule` 时读取为空，不从较新镜像补读，也不从 plannedDate、deadline 或提醒合成日程；下一次正常提交写空数组。键存在但坏 JSON、重复 ID、坏时区或悬空引用时进入恢复，保留原始数据，只有用户显式丢弃才可清理。日程的格式、绝对时间、IANA 时区与引用校验和备份使用同一模型规则；文件另有数量/字节预算。

Store 的 v3 覆盖、合并、失败回滚和提交前重算均携带完整日程集合；v1/v2 合并保留本机日程，覆盖将其清空并返回删除数量。任务/板/日程不能提交成半批状态。导入回滚也会推进发生变化的日程修订号，防止临时导入数据上的编辑覆盖已恢复内容。

文件默认 v3，v1/v2 继续可读但不能保存新增日程。显式降级需调用方确认损失并使用返回丢失条数的接口，详见 [备份格式](BACKUP_FORMAT.md)。旧可执行文件虽然能读带额外快照键的槽，重写时仍可能丢弃日程；回退前须保留完整 v3 备份，多卷须保留整套。旧版读取器不应读取 v3 文件。

## 变更数据模型时

1. 在 [models.dart](../lib/models.dart) 为新字段定义读取默认值或可空语义，并明确各旧版本降级的丢失范围。v3 的日程集合必须存在；旧库和 v1/v2 备份缺少集合时读取为空。
2. 更新 [import_preflight.dart](../lib/import_preflight.dart) 的字段白名单和必要校验；导入预检与 `DataMigrator` 不能出现互相矛盾的接受规则。
3. 确认本地保存、v3 备份往返、v1/v2 导入与有损导出的预期行为；用合成数据和完整分卷恢复验证。若改变文件契约，更新 [备份格式](BACKUP_FORMAT.md) 和独立验收记录。

本地运行时临时状态不要加入保存快照。字段的实际默认值、版本行为和兼容边界由模型、预检与相关测试共同约束。
