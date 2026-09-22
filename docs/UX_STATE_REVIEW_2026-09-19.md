# UX01–07 状态切换复审（2026-09-19）

基线：`main / 9c622fd`；开始时工作区干净。用户反馈双端实测未发现大问题，本轮补查隐蔽状态路径，不代替逐项设备验收，也不将 UX08 的 30 条场景全部标记通过。

结论：**复审当时仍有两条已复现的界面卡住路径（R1/R2），以及 R5/R3/R4。** 产品修复见 [状态交叉修复](UX_STATE_FIX_2026-09-19.md)（2026-09-19，自动化 358/358）；本文件保持复审原文，不把当时的失败写成已通过。复审当轮没有修改产品实现、提交 Git 或重打包。

## 验证证据

- 现有默认测试：`flutter test --no-pub`，**352/352 通过**。
- 静态检查：`flutter analyze --no-pub`，**0 issues**。
- 独立反例：`flutter test --no-pub test/review/ux_state_review_probe.dart --reporter expanded`，**5 个反例全部失败，失败符合以下缺陷预期**。
- 探针不以 `_test.dart` 结尾，不计入默认测试；修复时需转入正式回归集。仅使用合成任务和 mock SharedPreferences，无用户任务、密钥或真实 AI 请求。
- 本轮为源码追踪、组件测试及 Widget 平台模拟；没有操作真实 Android/Windows 应用，不将调试模式异常直接推定为 Release 崩溃。
- 本地忽略日志：`matrixflow-native/ux-state-review-baseline.log`、`matrixflow-native/ux-state-review-results.log`。SDK 缓存位于工作区外，测试通过获准的 SDK 访问执行。

## R1 / P1：退出淡出被重新聚焦打断后，内容永久透明

位置：`lib/widgets/quadrant_transition_layout.dart:155–162`；`lib/screens/matrix_screen.dart:603–608`。

复现：列表模式 → 聚焦 Q1 → 返回 → 在 220ms 淡出结束前点击底部 Q2 卡片。探针使用返回后 50ms 点击。

结果：新象限进入聚焦，淡出控制器却继续反向运行至 **0.0**，没有恢复到 1。父组件将 `_listExitFading` 清零，但子组件仅处理 `fadeOutOnly: false → true`，不处理 `true → false`。淡出完成时因标志已经清零也不再触发退出回调。`pumpAndSettle` 后主体保持透明，不能通过等待恢复；需再退出或切换其他状态才能恢复，非数据损坏。

修复要求：重新聚焦必须从当前透明度反向恢复至可见；过时退出回调不能清除新会话。建议用状态/代次统一处理 entering/focused/exiting，避免父组件布尔值和动画控制器各自推进。

## R2 / P1：淡出期间打开 Windows 详情会丢失退出回调

位置：`lib/widgets/quadrant_transition_layout.dart:94–98,123–133`；`lib/screens/matrix_screen.dart:427–433,459–469`。

复现：Windows 宽窗口（探针 1280×900），列表聚焦 Q1 → 返回 → 淡出 50ms 时点击还可见的任务标题，打开侧栏。

结果：详情正常打开，但列表永不回来。侧栏使布局从 `activeCenter` 变成 `Row → Expanded → activeCenter`，原过渡组件被卸载；新组件初始 `fadeOutOnly=true`、透明度 0，初始化既不启动动画也不报告完成。父组件 `_listExitFading` 一直为 true。主页 `PopScope` 也因此继续拦截返回，但已无 `_focusedQuadrant` 可执行退出，形成无自然完成出口的状态。

修复要求：不能把退出清理仅寄托于即将被重建的子组件动画。初始化为 exiting 时也必须安全完成；或者将过渡状态/控制器提升到稳定生命周期，并在退出期间禁用编辑等改变布局的操作。仅给构造函数补一个 `forward()` 会混淆进入和退出，不能完整修复。

## R5 / P2：减少动画的列表退出同步回调触发构建期 setState

位置：`lib/widgets/quadrant_transition_layout.dart:155–159,178–181`。

复现：开启减少动画 → 列表模式 → 聚焦 → 返回，不需要快速操作。

结果：`didUpdateWidget` 内设 `_listFade.value=0`，同步产生 dismissed 通知，直接调用父组件回调并 `setState`；探针捕获 `setState() or markNeedsBuild() called during build`。后面的帧后通知没有避免前面的同步调用，且存在重复通知路径。

修复要求：所有退出完成通知统一帧后调度、检查 mounted 和当前退出代次，并保证同一退出只通知一次。此项确认调试/Widget 异常，未声称真实 Release 一定崩溃。

## R3 / P2：进入非 Q1 象限会重建象限子树，提前取消完成反馈

位置：`lib/widgets/quadrant_transition_layout.dart:410–415,512–514`。

复现：宫格模式开启隐藏已完成 → 勾选 Q1 任务 → 在退场保留期内立即进入 Q2。探针验证进入前任务仍作为退场快照显示，进入的第零帧却已经消失。

根因：`orderedQuadrants` 改变 Stack 中象限顺序，但 `_buildRegion` 返回的最外层 `Positioned` 没有稳定 key。内部 `QuadrantPane` 的 key 不能跨父元素保留 State，因此退出缓存和相关动画状态被销毁。这违反“象限常驻同一子树”的实现契约。另一个诊断探针也曾确认进入 Q2 会改变 Q1 State 身份。

修复要求：给 Stack 的直接象限子节点稳定象限 key，验证 Q1–Q4 进入、互切及反向退出时的动画/滚动/拖拽状态。已有滚动回归只进入 Q1，恰好未改变初始象限排列，不能覆盖此问题。没有据此推断所有滚动都会丢失（PageStorage 可能恢复部分滚动）。

## R4 / P2：退场缓存冻结仍在场任务的旧排序

位置：`lib/widgets/task_exit.dart:78–85,102–110`。

组件反例：同一 epoch 依次输入 `[A,B]`、`[B,A]`，没有任何离场项，输出仍是 `[A,B]`。先按旧 `_order` 收集仍存在 ID，后续新顺序因 `seen.contains(id)` 被跳过。

影响：同一查询代次内，只要存量任务顺序发生变化，显示顺序就可能与 Store/查询结果不一致，持续至缓存重建或清空。该组件被宫格、列表、搜索、归档共用；归档上游明确按完成时间排序。**这里确认的是组件排序反例，没有额外宣称已经实机复现某一排序操作，更不是整机卡死。**

修复要求：以当前 items 的相对顺序为准，仅将正在离场的快照插入原位置，覆盖排序变化、撤销、新项插入、删除和混合离场。

## 建议修复与验收顺序

1. 一并梳理 R1/R2/R5 的列表聚焦状态与退出通知；加入打断后重新聚焦、退出期打开/关闭详情、窗口缩放、减少动画和快速返回测试。
2. 修复 R3 的直接子节点身份，再验证四象限互切与完成动画交叉。
3. 修复 R4 并增加缓存顺序回归。
4. 所有反例转绿、默认测试/analyze 通过后，再在真实 Windows/Android 上补快速操作路径验收。此次用户已有的“未发现大问题”反馈继续保留，不因新增反例否定已完成实测。
