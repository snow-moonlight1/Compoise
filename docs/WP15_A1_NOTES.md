# WP15-A1：纯模型与时间 API

状态：A1 实现说明。A1 不接 Store、备份或 UI；目标契约见 [WP15_CONTRACT.md](WP15_CONTRACT.md)。现有 [timezone 0.10.1](../pubspec.yaml) 是直接依赖，复用其内置 IANA latest_all 数据；本包未增加依赖或产品数据格式。

## A2 可接入的入口

| 文件 | 公共入口 | 用途 |
|---|---|---|
| [schedule_item.dart](../lib/schedule_item.dart) | ScheduleItem.timeBlock / .event / .fromJson / .toJson，ScheduleItemKind | 不可变、显式 id 的独立记录；解析只读已知字段，未知字段的提示由 A2 预检负责。构造时检验种类、时间、时区及 taskId/boardId 组合。 |
| 同上 | validateScheduleCollection(items, parentTaskIds, boardIds) | 在拟提交的**整套**任务、板、日程上查重和校验引用；传入父任务 id 集合，不包含子项 id。模型本身无法判断 id 所指任务是否存在。 |
| 同上 | overlappingScheduleItems(items, candidate) | 返回与候选记录相交的其他记录，保持输入顺序，供 UI 提示；重叠并不阻止保存。 |
| [schedule_time.dart](../lib/schedule_time.dart) | scheduleLocation(id)，ScheduleCivilDate，ScheduleWallTime，wallTimeCandidates，resolveWallTime | 同一份 IANA 时区规则；wallTimeCandidates 返回 0/1/2 个带偏移的绝对时刻。resolveWallTime 对不存在的墙上时间、未指定偏移的重复时间和错误偏移抛 ScheduleTimeException。拖动/表单须显示候选并显式选偏移。 |
| 同上 | scheduleIntervalsOverlap，clipScheduleInterval，dayWindow，weekWindow，clipToDay，clipToWeek，ScheduleSlice | 半开区间与按**调用方指定的显示时区**求日/周窗口；跨日片段用 continuesBefore/continuesAfter 标记。传入起止都是 Unix 毫秒，窗口不假定一天为 24 小时。 |

ScheduleItem.fromJson 仅检查记录自身字段；A2 在预检和本地快照读取时还须调用 validateScheduleCollection，并决定未知字段提示、保存错误展示和损坏恢复。A2 应对整个数组检查 id 唯一性，对任务删除/编组/撤销同步维护引用。保存字段为 id、kind、taskId 或 boardId、事件 title、startAt、endAt、timeZoneId；A1 尚未把它们接入 ExportData。

时区数据库首次调用时懒加载，避免平台各自的 DateTime 对 DST 歧义静默选边。时区偏移、候选绝对时刻和视图窗口都由同一 Dart 数据计算。调用方需把设备时区映射为 IANA id 后传入；Windows 等平台如何取得该 id 属于视图/集成包。不能传本地化显示名称或缩写代替 IANA id。已持久化时区在未来数据版本中不可识别时，A2 的恢复流程须保留原记录，不能吞掉异常后写空数组。
