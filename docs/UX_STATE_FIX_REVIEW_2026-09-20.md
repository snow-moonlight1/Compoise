# R1–R5 修复效果复审（2026-09-20）

基线：`main / 9c622fd` + 用户现有未提交的 R1–R5 修复。复审保留所有已有改动，仅新增补充探针与本报告，并同步交接说明；未修改产品实现、未提交、未重打包。

## 结论

**R1–R5 原始缺陷均已修复，原始 5 个反例和 6 个正式回归全部通过。但聚焦退出状态仍有一条相邻路径没有收口：淡出期间连续切换视图会停止退出动画并留下退出标志。** 因此可以确认原始修复有效，不能将整个退出状态机判定为已无卡住问题。

> 2026-09-20 随后：S1 已修复并转入正式回归；补充探针 7/7、全量 359/359。本文件保留复审当时的失败描述。

### S1 修复后的独立复核（2026-09-20）

**通过：原始 S1 卡住路径已关闭，本次检查范围内未发现新的阻塞性问题。** 核对的是 `9c622fd` 上现有未提交修复，没有 reset 或修改产品代码。

- 切换视图时同时清除聚焦中/淡出中的会话；Escape 与系统返回共用 `_finishListExitNow`；子组件切换模式时更新回调代次，并在仍需退出时帧后报告完成，修复与根因对应。
- 独立重跑原始 R1–R5 探针 5 项、补充探针 7 项、正式状态回归 7 项：合计 **19/19 通过**。S1 在 Escape/系统返回前已自行恢复列表，不依赖兜底掩盖问题。
- 在补充探针新增 S8（淡出中直接按 Escape，一帧恢复列表并可再次聚焦/退出）、S9（子组件淡出中切模式，完成回调去重且后续会话正常）；扩展后 **9/9 通过**。
- 全量 `flutter test --no-pub`：**359/359 通过**；`flutter analyze --no-pub`：**0 issues**；`git diff --check` 通过。
- 忽略日志：`matrixflow-native/s1-independent-targeted.log`、`s1-independent-extra.log`、`s1-independent-full.log`。探针仍需显式运行，不改变默认 359 项计数。
- 本轮仅补充测试和复核记录，未提交、未重打包、未实机。R1–R5/S1 可按代码与自动化复核关闭；下一步仍为 UX08 双端实机/全路径验收，不将此结论扩大为整个应用不存在任何状态问题。

| 项目 | 独立复核结果 |
|---|---|
| R1 淡出中重新聚焦后透明 | 通过；取消退出后透明度恢复，20 轮退出→再聚焦→再退出也能收敛 |
| R2 侧栏重挂丢失退出回调 | 原始路径通过；另测详情打开后缩窄移除过渡组件、再扩大重建也能恢复列表 |
| R3 象限重排销毁完成反馈 | 通过；原始第零帧快照和正式回归中的 Q1 State 身份断言通过，直接子节点 key 修复对应根因 |
| R4 退场缓存冻结排序 | 通过；活项重排、混合退场、撤销取消定时器、epoch 切换清理均通过 |
| R5 减少动画构建期 setState | 通过；原反例无异常，初始化为退出状态的完成回调也只通知一次 |

## S1 / P2：淡出中列表→宫格→列表会卡在退出状态

定位：

- `matrixflow-native/lib/screens/matrix_screen.dart:360`：切换视图时仅在 `_focusedQuadrant != null` 时清理聚焦退出状态。
- `matrixflow-native/lib/widgets/quadrant_transition_layout.dart:156–174`：切回列表时把 `_listFade.value` 设为 1；这会停止正在执行的淡出，但 `fadeOutOnly` 没改变，因此不再开始退出或通知退出完成。
- `matrixflow-native/lib/screens/matrix_screen.dart:318–335`：Windows Escape 没有 `_listExitFading` 分支，无法使用本轮新增的系统返回兜底。

复现（Windows Widget 键盘事件，1280×900）：

1. 列表模式进入 Q1 聚焦。
2. 点击返回，开始 220ms 淡出。
3. 30ms 后按 `Ctrl+Shift+L`，变成宫格；再过 30ms 按一次，切回列表。
4. 等动画稳定并额外等待 2 秒。

实际结果：设置值已经回到 `ViewMode.list`，但 `TaskListView` 不出现；继续按 Escape 也不恢复。调用系统返回的新增兜底后可以恢复列表。这是局部界面状态卡住，**不是整个进程无响应或数据损坏，也不是必须重启才能恢复**。

状态轨迹：

```text
聚焦 → 退出中（focused=null, listExitFading=true）
     → 宫格（清理条件漏掉退出中，退出标志仍为 true）
     → 列表（fade.value=1 停止动画，fadeOutOnly 仍为 true）
     → 没有后续 dismissed 回调，退出标志无法自然清除
```

此项来自修复范围的相邻交叉路径；未将其描述为此次修复新引入的回归。原始 5 项探针没有覆盖“退出中切换视图”。

建议：把视图切换作为明确的状态终止事件，覆盖聚焦中和退出中，统一清除 `_focusedQuadrant`、`_listExitFading`、`_listExitFrom` 并失效旧回调；或者确保子组件改动控制器时维持退出完成契约。Escape 应复用统一退出入口，避免与系统返回分叉。不能只恢复动画透明度而保留悬空退出标志。

## 本轮执行证据

- 原始探针 + 正式修复回归：**11/11 通过**。
- 默认全量：**358/358 通过**。
- `flutter analyze --no-pub`：**0 issues**。
- 补充探针 `test/review/ux_state_fix_review_probe.dart`：**6/7 通过，S1 失败**。其余通过项为 S2 连续 20 轮中断、S3 首个淡入 tick 前返回、S4 系统连续返回、S5 退出初始化通知去重、S6 撤销/epoch 定时器清理、S7 侧栏跨宽度卸载重建。
- 探针刻意不使用 `_test.dart` 后缀，不进入默认集；修复 S1 后应把相关断言加入正式回归。最初补充探针的 Store 释放时机造成定时器残留，已修正测试夹具并重跑，最终只剩 S1 产品行为失败。
- 本地忽略日志：`matrixflow-native/ux-state-rereview-original.log`、`ux-state-rereview-full.log`、`ux-state-rereview-extra.log`。
- 本轮未进行真实设备复测。上次用户实测反馈仍有效，但不等同于本轮修复版本已完成实机验收。

复跑补充探针：在 `matrixflow-native/` 执行 `flutter test --no-pub test/review/ux_state_fix_review_probe.dart --reporter expanded`。
