# WP15-A2：本地日程状态接入

状态：A2 实现说明，接在 [WP15-A1](WP15_A1_NOTES.md) 纯模型与时间规则之后。此包只处理本机 Store；目标行为见 [WP15 契约](WP15_CONTRACT.md)。备份文件仍按现有 v1/v2 规则运行，v3 属于 WP15-B。

## Store 接口

- Store.scheduleItems 返回不可修改的当前记录列表；记录对象本身不可变。Store.captureSnapshot().scheduleItems 和 scheduleRevisions 提供离线读取。
- addScheduleItem(item) 校验全库 id、父任务/板关联；重复或孤儿引用抛 FormatException。调用方提供稳定 id；Store 不代替 UI 生成 id。
- scheduleRevision(id) 返回当前会话修订号。updateScheduleItem(item, expectedRevision:) 和 deleteScheduleItem(id, expectedRevision:) 对不存在或已变更记录返回 false；相同内容更新返回 true 且不增加修订号。成功变更提交整库快照；启动恢复待处理时拒绝命令。
- 删除父任务、清空象限/板、删除板均在同一次状态变更里清理关联记录；删板还删除该板独立事件。删除任务的撤销快照包含关联记录，恢复时检测 id 冲突。编组把原任务关联重指向新父任务。任务改名、完成或跨板移动不改日程 JSON；关联记录的板归属由当前任务派生。

## 本地兼容与失败行为

新提交的双槽快照和兼容镜像均包含 matrixflow-schedule。读取旧提交槽时，该键可缺省并解释为空数组；不会从可能较新的镜像补读。键存在但不是合法数组、含坏 IANA 时区、重复 id 或孤儿引用时进入启动恢复，保留原始槽和镜像，不提交空数组。恢复复制内容包含新键；用户显式丢弃损坏数据后，才移除已失效引用并提交。

Store 当前仍只接收 v1/v2 备份：合并保留现有日程；覆盖把日程置空，并在原子提交失败时一起回滚。WP15-B 须把 v3 日程集合接入 ExportData、预检、导入预览/冲突、导出分卷和恢复模拟，同时补上覆盖预览中日程删除数量。当前 v1/v2 导出不携带日程，因此不能作为新增记录的无损备份。旧可执行文件重写本地槽也可能丢弃新键；发行前需按 [契约](WP15_CONTRACT.md)处理回退提示。

编组在现有产品中没有独立的“撤销编组”命令；若后续增加，该命令须保存并恢复每条记录原来的 taskId，不能只撤销任务结构。设备时区到 IANA id 的映射、Planner 视图和通知联动也不在 A2。
