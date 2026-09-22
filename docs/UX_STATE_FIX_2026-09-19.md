# UX 状态交叉修复（2026-09-19）

状态：R1–R5 与 S1 已实现、自动化通过；Android/Windows 实机未验。下一包仍是 UX08（全路径验收与文档收口），未把第 7.2 节 30 条标为已通过。

依据：[状态复审](UX_STATE_REVIEW_2026-09-19.md)、[UX 返修计划](IMPLEMENTATION_PLAN_2026-09-17_UX_REWORK.md) 第 5.2 / 5.3 节。基线 `main / 9c622fd` + 复审未提交文档。用户此前「双端实测未发现大问题」的反馈保留。

## 改动

### R1 / R5 · 列表退出淡出与减少动画通知

- `QuadrantTransitionLayout` 为每一次淡出/取消分配 `_listFadeGeneration`。重新聚焦时从当前透明度 `forward()` 回 1，过时代次的 dismissed 回调不再结束新会话。
- `fadeOutOnly: true → false` 现会取消退出；`false → true` 才开始退出。减少动画把透明度立刻设到终态。
- 退出完成一律帧后通知，且同一代次只通知一次；`didUpdateWidget` / 状态监听不再同步调用父组件 `setState`。

### R2 · 侧栏重挂不丢退出

- `MatrixHome` 给过渡组件稳定 `GlobalKey`，Windows 打开详情把布局从单栏改成 `Row` 时 State 与动画控制器继续活着。
- 若 State 仍被重建且一上来就是 `fadeOutOnly`，初始化直接完成退出，不再把退出误当成进入、卡在透明度 0。
- 父组件 `onFadeOutDone` 在 `_listExitFading` 已清时为空操作；系统返回在淡出卡住时也能强制结束退出。

### R3 · 象限子树身份

- Stack 直接子节点 `Positioned` 使用稳定键 `q-region-$q`。进入非 Q1 时 `orderedQuadrants` 重排不再销毁其他象限的 `QuadrantPane` State，完成退场快照得以保留。

### R4 · 退场缓存顺序

- `ExitRetention.sync` 以当前 `items` 相对顺序为准，只把正在离场的快照插回上次视觉下标。同一 epoch 内仍在场任务的排序变化不再被旧 `_order` 冻结。

### S1 · 淡出中切换视图

- 视图模式变化在 `_focusedQuadrant != null` **或** `_listExitFading` 时都清掉焦点会话，避免淡出被宫格/列表切换停掉后标志悬空。
- Escape 与系统返回共用 `_finishListExitNow()`。子组件在切视图时作废旧淡出代次；若仍是 `fadeOutOnly` 则立即完成退出，不再把透明度拉回 1 却不通知。

## 测试

- 新增默认集 `test/ux_state_regression_test.dart`（7 项）：R1 淡出中点卡片恢复透明度、R2 桌面侧栏仍能完成退出、R3 进 Q2 第零帧快照仍在且 Q1 State 同一实例、R5 减少动画退出无构建期异常、R4 活项重排 + 离场项插回原位、S1 淡出中两次切换视图仍回列表。
- 复审探针 `test/review/ux_state_review_probe.dart`、`test/review/ux_state_fix_review_probe.dart` 仍不进默认集。

## 验证

- `flutter analyze --no-pub`：**No issues found**。
- 定向 `test/ux_state_regression_test.dart`：**7/7**；补充探针 **7/7**。
- 全量 `flutter test --no-pub`：**359/359**（352 + 7）。
- 未重新构建双端 Release，未启动真实 Android/Windows 应用。
