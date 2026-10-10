# WP15-C2：Planner 日程编辑与移动

基线：`ea6c4d0d8e58dd15e4c68d9824c9c0ac0bb445c6`。分支：`codex/wp15-c2`。本包在已有 C1 页面上接入 A2 命令，没有重新移植 C1，也不代表 WP15-D 或整项 WP15 已验收。

## 接入与改动边界

`PlannerScreen(displayTimeZoneId: currentDeviceIanaId, store: store)` 可直接挂载；也可从 Provider 读取 Store。注入 `snapshot` 时保留只读模式。显示时区仍由调用方明确提供，不按 UTC 偏移猜地区；设备时区发现与首页入口由集成/D 包处理。

变更限于 `lib/screens/planner_screen.dart`、新增 `lib/planner/` 编辑/手势代码、各语言开头 schedule 文案、`test/wp15_c2_*` 与本文。未修改 Store、日程模型/时间规则、备份、平台工程、首页/OCR、路线图或 WP15 契约。

## 用户流程

- 默认页面只增加“添加日程记录”。时间块明确选择现存父任务；事件明确选择父任务或看板。不预填结束时间，不假设默认时长，不新增跨度上限。点击空白网格可建议开始日期/钟点，仍须用户选择结束并核对。
- 点记录先看详情，再进入编辑；更多菜单提供移动、起止调整、显示手柄与删除。编辑不转换 kind，恢复原 IANA 时区、偏移和毫秒端点；任务的计划日与截止日仅作日期参照，不改提醒、象限或任务状态。
- 表单先“核对更改”，展示关联、完整起止日期/钟点/UTC 偏移、IANA 时区和实际时长。重叠记录列出完整时段，须明确勾选保留重叠才能保存。核对后新出现或改变的重叠会要求重新核对。
- 删除另有确认，只向 Store 删除该 id。提交前取消不写入。相同内容编辑沿用 A2 的无操作行为，不增加 scheduleRevision。
- 按住记录拖动；更多菜单按需显示两端手柄。网格以实际经过时刻映射到当前显示时区，每 15 分钟给一个可在表单修改的建议钟点。拖放进入同一核对/校验流程，不直接落库。跨日片段也操作整条记录：拖放目标是整条记录的新开始时刻，确认页展示完整端点。移动保持实际毫秒时长；起止调整保留另一端点与原关联，确认后记录时区更新为显示时区。触屏或键盘均可通过表单完成同一动作。
- A1 拒绝不存在的 DST 墙上时间；重复时间逐端展示 UTC 偏移选项。编辑还原原候选；拖放建议不自动选择重复时段的候选。午夜、跨日/跨周、23/25 小时日继续遵循 A1/C1 半开区间规则。

## 并发与持久化

编辑打开时捕获 scheduleRevision，手势在拖动前捕获它。外部改写、删除或重新引入同 id 会阻止旧表单/手势覆盖当前记录。等待 flush 时禁用重复提交与关闭；没有第二套日程状态或持久化入口。

接受 Store 命令后等待 `flush(waitForReminders: false)`，只有持久化成功且该记录仍匹配已接受的结果才提示成功。失败明确显示“内存已更改、尚未保存”；重试调用现有 `retrySave(waitForReminders: false)`，不重放添加/更新/删除命令，也不再增加日程修订号。此阶段关闭会保留待保存更改，页面也提供库级重试。startupRecovery 期间禁写。未发现阻塞本包的核心 API 缺口。

## 自动化验证

SDK：`D:/Dev_SDKs/Flutter_3.32.8/bin/flutter.bat`。

```powershell
& D:/Dev_SDKs/Flutter_3.32.8/bin/flutter.bat test --no-pub test/wp15_c2_edit_session_test.dart test/wp15_c2_planner_editor_test.dart test/wp15_c2_drag_test.dart test/wp15_c1_schedule_layout_test.dart test/wp15_c1_planner_screen_test.dart test/wp15_schedule_model_time_test.dart test/wp15_schedule_store_test.dart --reporter expanded
& D:/Dev_SDKs/Flutter_3.32.8/bin/flutter.bat analyze --no-pub
```

定向与必要回归共 **93 项通过，exit 0**，其中 C2 新增 37 项。分析 **No issues found，exit 0**。覆盖取消、相同值、过期编辑/拖动、添加/更新/删除的失败与重试、等待保存防重复、恢复禁写、DST 两种异常、毫秒精度、跨日/跨周与午夜、重叠确认、实际拖动及两端调整、320px/3 倍字号、键盘与语义。

本轮按集成会话指令未跑全量测试或云端检查，待合并后统一执行。没有提交生成文件、缓存、库数据或测试日志。

## 未验收

Android、Windows、Linux 原生设备上的手势精度、鼠标/触控、实体键盘、原生读屏与字体仍需实测；设备 IANA 时区发现、运行中切换时区以及原生 DST 样例由 D 包验收。首页导航、任务主入口和最终整库/云端门禁由集成者统一处理。本包不涉及外部日历、通知联动或循环事件。

2026-10-10 的计划页改动没有回头改这份 C2 记录里的当时行为。空白网格单击建议开始钟点只描述 C2 当时的页面；现行产品不再从空白网格新建，见 `WP15_CONTRACT.md` 第 6 节。
