# 基础修复二次复审（2026-09-16）

> **后续返修记录：** 本报告保留二审时的失败证据与判断。本轮之后 SR01–SR07 的修复及 305 项默认回归结果见 [二审返修记录](FOUNDATION_SECOND_FIX_2026-09-16.md)，不改写下文历史实测结果。

复审对象：`main / 3a711c87d9cd25e4b14c6508c47a4c8b26ac41bb` 上尚未提交的 F01–F22 修复。工作目录 `D:\Dev_project\martix`。本轮未修改产品实现、未提交 Git、未启动应用、未使用真实待办或密钥；保留开工前所有改动。

**结论：需要打回继续修复。“所有可本地代码问题已修完”不成立。** 280 项默认测试确实通过，但新反例复现了提醒生命周期、冷启动导航、草稿退出、模型配置和子项热区的遗漏。设备验收不是当前唯一剩余工作。

## 验证记录

| 检查 | 本轮结果 |
|---|---|
| `flutter test --no-pub --reporter expanded` | 280/280 通过 |
| `flutter analyze --no-pub` | 0 issues；包含新增二审探针 |
| 原 `test/review/wp28_review_probe.dart` | 8 通过、13 失败；多处旧 fixture 在 Widget 测试结束前未销毁 Store 的周期 Timer。不能把这 13 项一概当作产品失败 |
| 新 `test/review/foundation_second_review_probe.dart` | 7/7 在对应业务断言失败；无 pending Timer 或重复 dispose 造成的失败 |
| Android / Windows Release | 本轮未重建，上一轮报告为通过；本轮不将其当作独立复验结论 |
| 真机、系统托盘、热键、真实通知 | 未运行，不操作真实存档 |

新探针有意保留为显式运行文件，不改变默认 280 项数量，不删改已有回归断言：

```powershell
cd D:\Dev_project\martix\matrixflow-native
& D:/Dev_SDKs/Flutter_SDK/bin/flutter.bat test --no-pub test/review/foundation_second_review_probe.dart --reporter expanded
```

本机忽略日志：`review-second-tests.log`、`review-second-analyze.log`、`review-second-probe.log`、`review-second-new-probes.log`。后续修复应把新增反例迁为默认回归。

## 必须返修的发现

### SR01 · P1 · F06：取消仍不能覆盖整个异步排程/恢复生命周期

- 位置：`lib/services/reminder_service.dart:753–765,783–843`。
- S01：让原生 `zonedSchedule` 已发出但未完成，此时 `cancelReminder` 直接调用插件取消；随后排程完成，仍留下该任务的原生待发记录。版本号只阻止调用前的排程，无法清理已发出的请求。此探针检验生产服务的调用顺序，未声称已经观察到真实系统横幅。
- S06：`rescheduleAllFuture([Alpha, Beta])` 正在等待 Alpha 的排程时执行 `cancelAll`；Alpha 完成后，恢复循环继续为 Beta 创建新的版本号，最终 cancelAll 之后仍有 Beta 待发。这个反例即使 cancelAll 自身已排队也存在。
- 现有 R14 仅覆盖等待权限检查时取消，没有覆盖上述两种交错。
- 修复要求：单项取消与排程使用同一有序生命周期；恢复/导入遍历具有批次失效令牌，清空、覆盖导入等应让旧遍历停止。补取消在排程前/中/后、恢复中清空及覆盖导入的生产服务回归。

### SR02 · P2 · F09：冷启动不是“代码已修待实测”，仍有确定的递归错误

- 位置：`lib/main.dart:16–19`，`lib/services/reminder_service.dart:426–438,487–499`。
- main 传给 init 的回调读取 `ReminderService.instance.onNotificationSelected` 再调用它；init 恰好把此回调保存为同一属性。main 等待 init 完成后才 runApp，冷启动载荷到达时导航尚未注册，于是回调调用自身。
- S02 使用与 main 相同的启动回调及合成 launch details，实际输出 `Failed to read notification launch details: Stack Overflow`；挂接页面回调后收到 0 个载荷。
- `_consumedLaunchPayload` 已设置，载荷也没有进入 pending 队列，不能靠页面稍后挂接恢复。
- 修复要求：启动阶段只缓存载荷，Store/导航和首帧 ready 后消费一次，取消自引用转发；父任务和子任务定位一并测试。当前 MatrixHome 也未把 payload.subtaskId 传到详情高亮参数。

### SR03 · P2 · F12：搜索/已完成页的返回按钮仍直接丢弃宽屏草稿

- 位置：`lib/screens/search_screen.dart:181–188`，`lib/screens/completed_screen.dart:194–197`。
- S03 通过真实搜索入口打开任务、修改标题、点页面返回。页面退出，没有丢弃确认，草稿消失。
- 原因：按钮直接 `Navigator.pop(context)`，不经过 `_protectDetailDraft`；详情中的 PopScope 不会把程序式 pop 变成 maybePop。
- 修复要求：页面返回、系统返回、详情关闭使用统一出口；补搜索和已完成两页，不只验证矩阵切任务及底部详情的 maybePop。

### SR04 · P2 · F16：同服务商换 Key 后迟到模型响应仍覆盖配置

- 位置：`lib/screens/settings_screen.dart:120–143,390–392,570–589`。
- S04：Key A 开始发现模型，切为合成 Key B，A 返回 `obsolete-model`。模型从用户原选 `chosen-model` 被写成 `obsolete-model`。
- 代次只在切服务商/新请求时更新；Key、Base URL、协议或手选模型变化没有统一使旧响应失效。请求还接收共享可变的 `store.aiConfig`。
- 修复要求：请求持有配置快照，以完整配置身份和选择代次判断能否应用结果；所有相关字段变化统一取消/收尾。至少补 Key、URL、协议和手选模型四条回归。

### SR05 · P2 · F12：脏草稿缩窄窗口只是强留宽屏侧栏，造成布局溢出

- 位置：`lib/screens/matrix_screen.dart:365–385`；搜索/已完成页使用类似固定宽度逻辑。
- S05：1400×950 打开详情并修改标题，缩到 360×800，得到 `A RenderFlex overflowed by 2.0 pixels on the right.`。340 dp 侧栏继续占据横向布局，矩阵只剩极窄宽度。
- 修复要求：在保留编辑状态的前提下切换为可用的窄屏详情容器，或在切换前统一处理草稿；不能把“仍留在树中”当作尺寸变化已验收。

### SR06 · P2 · F19：只修父任务热区，子项仍是 28×28 dp

- 位置：`lib/widgets/task_card.dart:365–367`。
- S07 经真实矩阵展开子项，测量完成手势节点，宽高均为 28 dp，未达到要求的 48 dp。
- 修复要求：子项的实际独立手势区域也达到 48 dp，回归边缘点击不会落到行编辑或空白。父任务 R18 通过不能覆盖子项。

### SR07 · P2 · F11：排程失败仍未反馈给用户

- 位置：`lib/services/reminder_service.dart:403–404,744–747`。
- 未来排程失败不再立即 show，这部分修正成立。但错误仅写入 `@visibleForTesting lastScheduleError` 和 debugPrint；全库没有产品 UI/Store 消费该错误，也没有每任务失败状态或失败重试入口。
- 用户仍看到正常的提醒字段/闹钟图标，却不知道未来通知未安排。权限提示不能代表排程成功。
- 证据为现有 R21 的失败注入路径及静态调用链；没有新增独立编号探针，不能把 7 个探针与 7 项发现一一对应。
- 修复要求：保存任务和提醒时间，同时将生产排程结果映射为可见失败状态及重试动作；成功重试清除错误；补真实入口的失败反馈回归。

## F01–F22 状态复核

“本轮未发现新增反例”只表示现有代码与自动化证据支持对应修复，不表示所有设备边界已验收。

| F 编号 | 二审意见 |
|---|---|
| F01/F02/F03 | 跨任务隔离、整份损坏拒绝、字段合并有实际改动及回归，本轮未发现新增反例 |
| F04 | 已有真实插件调用，不能再称纯模拟；仍待系统验收。另需检查托盘失败仍标 initialized、托盘退出两次 destroy、热键冲突状态无 UI 消费的问题 |
| F05 | 权限申请/拒绝保存路径有回归；Android 新装权限仍待实测 |
| F06 | **未修完，SR01** |
| F07 | 删除子项取消逻辑有回归，但可靠性仍受 F06 影响 |
| F08 | 初始化等待/启动排队已有修复；恢复整体生命周期仍受 SR01 影响。初始化失败被吞且 `_initCompleter` 不复位，后续重试路径还需补验 |
| F09 | **未修完，SR02，不能只标待实测** |
| F10 | 原生成功不再创建 Timer，有回归；真实横幅次数未实测 |
| F11 | **部分修复，SR07** |
| F12 | **未修完，SR03/SR05** |
| F13/F14/F15 | 象限/完成历史/撤销原反例已有回归，本轮未发现新的确定反例 |
| F16 | **未修完，SR04** |
| F17/F18 | 自定义思考开关/原大字聚焦反例已有回归；设备边界仍需实测 |
| F19 | **部分修复，SR06** |
| F20 | 合成 composing 回归通过；真实 Windows IME 待实测 |
| F21 | 保持包名、提供两条路线而不擅改是合理处理；迁移仍未验收，需用户决定及安装验证 |
| F22 | 缺签名拒绝的 CI/Gradle 配置已加入；本轮未执行远端 CI 或正式证书验证，不等于发行链路已完成 |

## 文档与发行的额外边界

- `docs/PRIVACY_POLICY.md` 仍有“安全明文”“encrypted or sandboxed”及一概称“官方 HTTPS 接口”的表述；原报告已指出它们与自定义 URL/明文备份事实不一致，本轮修复未更正。正式发布物料仍需校正。
- F21 不是必须立即替用户改包名的问题；先修上述确定的本地代码遗漏，再决定升级路线。禁止让用户先卸载旧版。
- 日期 picker 的远期 deadline 上界、命令面板/通知切板的一致草稿入口等原报告第 4 节缺口未因此关闭。
- 本轮不追加功能 CHANGELOG，避免把复审文档当成功能修复发布。下一轮应先修 SR01–SR07，不领 WP10/WP29/UI 实验。

**验收门槛仍未达到：除设备和签名/包名决策外，现有实现还有明确可本地复现的失败。**
