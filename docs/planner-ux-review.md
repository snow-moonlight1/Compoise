# 日程计划页 UX 走查（第 3 轮）

视角：产品经理 + 普通手机用户。结论分三类：已修复、已知取舍、建议后续处理。

## 已修复（本 PR）

| # | 问题 | 处理 |
|---|------|------|
| 1 | 「更多」里「日程计划」「导入截图」背景与其余项不一致 | 两项并入 `HomeMorePanel`，与其他项同一背景；日程计划移出「更多」 |
| 2 | 日程计划藏在「更多」，到达成本高 | 首页底栏改为「搜索 / 添加 / 日程 / 更多」，桌面顶栏同样多一个「日程」按钮；日程页左上角有返回「任务」的按钮 |
| 3 | 点一下任务池就拉到整页 | 任务池点按只展开到约 30% 屏高，可再拉到半屏 / 接近全屏，松手按最近一档吸附 |
| 4 | 首页与任务池数量对不上 | 任务池原先排除「已有日程的任务」，且默认显示所有看板；现统一为「当前看板的全部未完成任务」，已排程的卡片带小标记；入口把首页当前看板传入。|
| 5 | 详情面板像开发者页面 | 重做为底部详情卡，只显示标题、任务名、象限标签、日期+起止时间、时长；图标按钮「编辑 / 删除」；不再显示 UTC、时区名（仅在日程时区与当前显示时区不同时用一句话提示）、微秒 |
| 5 | 「编辑日程记录」等术语 | 全局改为「编辑日程」等（中文去掉「日程记录」，英文 / 日文本就是 schedule item / スケジュール項目） |
| 5 | 三点菜单（移动 / 调整 / 手柄 / 删除） | 去掉。手机：点日程块选中，出现上下圆形手柄（48dp 触控区）；长按整块拖动；桌面：鼠标移到上下边缘显示上下箭头光标，可直接拖 |
| 6 | 重叠只能「确认后保留」 | 数据层本来就允许重叠（`validateScheduleCollection` 不查重叠）；去掉核对 / 勾选确认流程，保存即并存；时间线并排分列；块上显示「与另 N 项同时」；保存后 SnackBar 提示重叠并可撤销 |
| 7 | 滑动切换象限无动画、无提示 | `PageView` + 联动下划线指示器；标签可点；首次展开显示一次轻提示；「减少动画」时直接跳转 |
| 7 | 无新手引导 | 首次进入弹出 6 步引导（可跳过，只出现一次，设置里「日程计划引导」可再次查看，日程页 ☰ 菜单里也有入口） |

## 走查中发现并已直接修复

- 删除没有退路 → 删除后立即显示「已删除日程」+ 撤销；拖动调整 / 拖入排程 / 编辑保存后都有带撤销的提示。
- 拖动日程块后弹出整套确认表单 → 直接生效，15 分钟吸附，拖动中实时显示起止时间，松手后提示并可撤销。
- 日视图总是从 0:00 开始，首屏全是空白夜间 → 默认滚动到 7:00（今天则为当前时间前 1 小时）。
- 当天没有日程时是一片空白 → 一行淡色提示。
- 周视图底部的操作说明文字 → 去掉。
- 夏令时「出现两次的时间」要求用户选 UTC 偏移 → 表单自动取较早的一次，不再向用户暴露偏移。
- 编辑表单：改开始时间时结束时间跟随（保持时长）；结束早于开始给出明确提示；标题必填提示。
- 触控区：工具栏步进按钮 32→40dp；任务池「+」为 48dp；象限标签整格可点（高 48dp）；手柄触控区 48dp。
- 选中日程块时自动滚动，避免被底部小工具条遮住；选中时任务池自动收起；开始拖任务时取消选中。
- 点击时间线空白处取消选中；周视图空白处同样。
- 「减少动画」（系统设置）下：日期切换、任务池展开、象限切换、引导翻页都不再播放动画。
- 看板筛选只有多于一个看板且已筛选时，任务池标题栏才显示看板标签。

## 取舍 / 无法在 box 上验证

- 手势（长按拖动、拖手柄、边缘自动滚动、双指缩放）只在 widget 测试里用模拟指针验证；真机手感（长按时长、手指遮挡、手柄大小）需要在手机上试用后再调。
- 新手引导和「象限滑动提示」的「已看过」标记存放在独立的 SharedPreferences 键（`compoise-planner-guide-seen`、`compoise-planner-tabhint-seen`），而不是首页教程的 `matrixflow-has-seen-onboarding`：后者属于库数据，参与备份、启动恢复和存档协议，新增一个字段会牵动这些契约。独立键不进入备份，换机后会再看一次引导。
- 编辑日程时，时间按「当前显示时区」解释；保存后记录的时区会更新为显示时区（起止时刻本身不变）。
- 拖动日程块时只做同一天内的纵向移动（上下拖）；跨天移动请用编辑里的日期选择。周视图里仍可长按把块拖到另一天。

## 建议后续处理（未做）

- 任务预计时长字段（任务模型目前没有），有了之后拖入时按预计时长定占位高度。
- 任务池卡片的「预计时长」展示依赖上面的字段。
- 时间线双指缩放改变小时高度（目前双指只用于日 ↔ 周切换）。

## 第 4 轮（真机反馈）自查与处理

原则：少层、少字、少滑动、少提示。

| 问题 | 处理 | 位置 |
|------|------|------|
| 手柄靠右，像只有它能拖 | 手柄居中于上/下边缘中点，并沿整条边画一条细线；整条边（48dp 高）都能拖 | `planner_block.dart` |
| 到处是 Toast / 撤销条 | 成功和细碎操作（保存、拖动、移动、拖入成功、重叠）不提示；删除先弹居中确认框（取消/删除）；失败一律提示（见下「提示规则」） | `planner_screen.dart`、`schedule_editor.dart` |
| 浮层最多叠 4 层；新建与编辑样式不同 | 新建/编辑统一为同一个居中 Dialog（屏宽−48，最大 420，键盘弹出可滚动）；详情卡改成选中块旁的单行小工具条（时间·时长＋编辑/删除图标），编辑时工具条让位；展开任务池会取消选中，选中会收起任务池 | `schedule_editor.dart`、`planner_detail_card.dart`、`planner_screen.dart` |
| 周视图标签横向滚动、「+N」折叠 | 标签自动换行（Wrap），行高随当天条数增长，整页上下滚动；去掉「+N」「还有 N 项」；汇总改为「共 1 小时 30 分钟」，无日程显示淡色「无日程」；去掉底部说明文字和「共 N 项 · 已完成」 | `planner_week_view.dart`、`l10n.dart` |
| 并行列宽按全天最大并发 | 按「重叠簇」各自分列：单独的日程占满宽度，簇内才按该簇最大并发等分；日视图不再横向滚动，也没有「还有 N 项」 | `schedule_layout.dart`、`planner_day_timeline.dart` |
| 刻度文字贴屏幕左边 | 时间线、日期条、周视图、工具栏统一 12dp 水平边距（`plannerPageMargin`），页面在 SafeArea 内 | `planner_day_timeline.dart` 等 |

其余自查：
- 顶栏：窄屏（<480dp）不再显示 ◀ ▶，上一/下一天（周）移入 ☰ 菜单，日期条和左右滑动仍可换周；大字体（>1.3 倍）时整行等比缩小而不是裁切。
- 引导第 3 步文案改为「拖手柄或拖边缘都行；编辑/删除在小工具条」。
- 浅色块上的小字使用 onSurface / onSurfaceVariant，对比度足够；深色主题沿用同一套 colorScheme。
- 空状态：日视图一行淡色提示，周视图每天「无日程」。

仍需真机确认：小工具条固定在底部任务池上方而非贴在块旁边（块在屏幕底部/很短时贴边定位容易被遮挡，所以选了固定位置）；窄屏 4 列并行时每列约 70dp，标题会省略。

## 提示规则（第 4 轮修正）

- **成功静默**：保存、调整时间、移动、拖入排程成功、编辑成功都不提示，删除成功也不提示、没有撤销条。
- **失败必须说人话**：展示为 SnackBar——同一时刻只有一条（新的先 `clearSnackBars` 替换旧的）、约 4 秒自动消失、带关闭图标、不带撤销，浮在任务池收起条（选中时还有工具条）上方，不遮挡它们。
- **对话框内的错误**（结束早于开始、时间不存在、保存失败等）显示在对话框里的行内文字，不弹 SnackBar，也就不会和对话框叠层。
- 文案（中文）：保存失败「保存失败，请重试。」；时间不合法「结束时间要晚于开始时间。」（对话框内）/「无法保存，请检查标题和起止时间。」；夏令时空档「这个时间不存在（当天夏令时切换），请换一个时间。」；日程已被改/删「这个日程已被修改或删除，已为你刷新。」；任务不存在「这个任务已不存在，已为你刷新。」；删除失败「删除失败，请重试。」；拖入失败「放不到这里，请换个时间再试。」；数据需要恢复沿用「已保存数据需要恢复，暂时无法显示日程。」。英文 / 日文同步。
- 实现：`planner_screen.dart` 的 `_fail()`；文案键在 `l10n.dart`（`scheduleEditorUnsaved/Stale/Gap/Invalid`、`scheduleTaskMissing`、新增 `scheduleDeleteFailed`、`scheduleDropFailed`）。

## 第 5 轮（真机反馈）

| 问题 | 处理 | 位置 |
|------|------|------|
| ◀ ▶ 被塞进菜单 | 菜单里不再有上一/下一天。日视图整块时间线左右滑动切日（左滑=后一天，右滑=前一天，带翻页滑动动画；双指缩放时忽略；竖向滚动、手柄拖动、长按移动、任务池拖拽互不影响）；窄屏顶栏不放 ◀ ▶，宽屏（≥480dp）保留 | `planner_day_swipe.dart`、`planner_toolbar.dart` |
| 「今天」常驻右上角 | 只有查看的日/周不含今天时，在日期标题旁出现小胶囊「回到今天」，在今天时不显示；不浮在页面上，不多叠一层 | `planner_toolbar.dart` |
| 手柄沿边画线 | 去掉线，只保留居中两个圆形手柄（整条边仍可拖） | `planner_block.dart` |
| 日程入口像二级页 | 见下「任务｜日程」同级切换 | `matrix_screen.dart`、`home_actions.dart` |
| 日期条一滑跳整周 | 改成 PageView：跟手，轻轻一碰会弹回本周，真正滑动才翻一周并带动所选日期 ±7 天；圆点覆盖所有周 | `planner_date_strip.dart`、`planner_screen.dart` |
| 周视图每个标签独占一行 | 标签宽度 = 文字宽度（有上限，过长省略），Wrap 并排，放不下才换行 | `planner_week_view.dart` |
| 周视图竖线没穿过圆心 | 每行自己画一段穿过圆心的线（x、y 都由同一组常量算出），行间首尾相接，从第一个圆心开始 | `planner_week_view.dart` |
| 任务池收起后下方大片空白 | 周视图改为 `CustomScrollView + SliverFillRemaining`，轴线一直画到任务池收起条上沿；日视图滚动区撑满，并在底部留出收起条高度，23:00 不被遮住 | `planner_week_view.dart`、`planner_day_timeline.dart` |

### 「任务｜日程」同级入口：调研与选择

- **TickTick**：底部 Tab（任务｜日历｜…），两者是同级主视图，可自定义 Tab，各自保留状态。
- **Tasks.org**：左上列表标题（点开切换列表）+ 日历是独立视图，列表选择留在标题处。
- **Android 官方导航指南**：2–5 个顶层目的地用底部 NavigationBar，每个目的地各自保留返回栈。
- 选择：**顶部整宽两段切换「任务｜日程」**，看板选择保留在任务页左上标题。理由：①底栏本来就只有搜索/添加/更多，再塞第四项正是用户嫌挤的地方；②改成底部「任务｜日程」两项会让搜索、添加、更多离开底栏，波及现有功能与测试；③顶部切换在手机和 Windows 桌面上表现一致，且两页同级、IndexedStack 保活，各自保留状态；日程页不再有「←」。
- 日程页内的 ☰ 菜单里有时区、看板筛选和引导；任务页的搜索/添加/更多不变。从任务详情「安排时间」进入的日程页仍是带返回箭头的独立页面（它是从任务派生的流程）。

### 自查补充

- 周视图每天的标签行距随条数自适应，没有横向滚动，也没有折叠；今天高亮保留。
- 桌面宽窗口下切换条限宽 560dp 居中，避免整屏拉伸。
- 顶栏：日期标题可省略，「回到今天」胶囊只在需要时占位；大字体下整行等比缩小。

## Round 6

- **Week axis**: seven circles split the axis into eight equal parts (circle *i* at i/8 of the visible height, under the header and above the pool bar). Each row is at least one slot tall with the circle at the row's vertical centre; a day with many labels grows its own row and the page scrolls. Line runs the full height.
- **Text centring**: week labels and day-block text are left-aligned and vertically centred; the drag preview shows the live title and times; a block under ~40dp shows one line "title time" (ellipsis, no overflow).
- **Motion**: pool open/close uses easeOutCubic (280ms; 220ms when folded by selecting a block). Dragging follows the finger without a curve. The ☰ menu uses easeOutCubic 180ms / 120ms out. "Reduce motion" makes all of these instant.
- **Add-mode buttons**: three equal slots in one row, selection is colour only (no check mark), so size/position/dialog height never change. Other ChoiceChips (deadline presets, quadrant picker, settings) also no longer show a check mark.
- **Pool bar → opened**: the dots and counts are one shared layer driven by the sheet height; they glide from the folded bar to their quadrant tab while the two headers cross-fade.

## Round 7

Changes: week axis starts at the first circle (nothing above it), circles one slot apart, line continues under the last circle to the pool bar; Tasks↔Schedule switch slides + fades (easeOutCubic 250ms, state kept, instant with reduce motion); dragged previews (pool task, week block) sit up-left of the finger and stay on screen (`planner_drag_feedback.dart`); the hovered week day is tinted.

Self-check sweep (problem → fix):
- Back key on the Schedule tab left the app with a selection / open pool → back now closes dialog, then selection, then folds the pool, then returns to Tasks, then leaves.
- A drag could carry a block past 0:00/24:00 → move/resize are clamped to the day window (still 15-min snapped, ≥15 min long).
- 320dp wide with "Back to today" shown: date row overflowed → toolbar scales down instead; toolbar height capped at 72dp for huge fonts.
- Mid-height blocks overflowed at 2× font → extras (overlap badge, 2nd title line) drop first, then one-line "title time".
- Landscape phone: date strip + toolbar left almost no grid → strip hidden when the window is shorter than 480dp (picker/swipe still change day).
- Test harness never changed the media query size (only the layout), hiding width-based branches → `c2Pump` now sets the real window; a sweep test covers 5 sizes × 1/1.3/2× text × light/dark through day, pool, week, selection and editor with no overflow.
- Covered by tests, no change needed: day/week stepping across month/year/leap day/DST day, tab state kept, reduce motion, drag preview on screen near edges.

Not verified / not fixed: real-device feel of drag previews and tab slide; screen-reader pass (semantics labels unchanged since Round 4); dark-theme colour contrast was only checked for overflow, not measured; the time bubble while resizing still sits above the block edge, not above-left of the finger.

## Round 8

- "Back to today" shows only in the day view away from today; the week view never shows it, so the range title is not squeezed (rows under 360dp wide scale down instead of ellipsizing the title).
- Week label drag: the original stays in place at ~0.38 opacity; the preview is the label itself (same colour, bar, text, **same size**), its lower-right corner ~10dp past the finger (clamped on screen). The pool-task preview uses the same small offset (`plannerDragOrigin`); everything else unchanged.
- Fixed while testing: the hovered-day tint swapped the row's widget tree, which could drop the drag mid-air; the tint box is now always present.
- Not verified on a device: preview feel under a thumb; the real date-range title width at 320dp (tests use a wide font).

## Round 9

- "Back to today" left the toolbar entirely (the date title is never squeezed). It is now a 48dp round button, bottom right, just above the pool bar (clear of its "+"), showing 今 (zh/ja) or T (en) with the tooltip/label "Back to today". Shown only when the viewed day (day view) or week (week view) does not contain today; tap = jump to today, mode kept. Hidden while the pool is open or a block is selected (so it never meets the pool or the selection bar). Fades/scales in; instant with reduced motion.
- Week view: the "Week N" row is gone (l10n key `scheduleWeekNumber` removed); the axis now starts at the top and its length is the whole area, circles still evenly spaced, line to the pool bar.
- Pool opens to 33% of the page. A tap on empty content folds an open pool (a plain `Listener`: it never joins the gesture arena, so blocks, handles, swipes and drags are unchanged; taps that move >12dp or last >300ms do not count). Tapping a block still selects it (which also folds the pool).
- Not verified on a device: feel of the button position on gesture-nav phones; the "tap block folds + selects" path is covered only for a block that is visible with the pool open.

## Round 10

- Today button: 56dp, 22dp from the right edge and 22dp above the pool bar (still clear of its "+").
- "Schedule time" in a task's detail no longer pushes the old full-screen planner page from the home page (phone sheet or side panel): the detail closes and the home page switches to the Schedule tab (same slide, state kept, back key as before) with that task as the focus task (`TaskDetailSession.onScheduleTime` → `_scheduleFromDetail`, `PlannerScreen.focusToken`). The old route stays for the other pages that still use it (Today, Search, Completed).
- Pool focus: the pool no longer grows to the half height for the highlight; it opens to the usual third at most, switches to the task's quadrant tab, lists the task first (display only, stored order unchanged) and outlines it. Touching the lists/pages, a tab, a drag, or tapping empty space ends the outline.
- Not verified on a device; focus from Today/Search/Completed still opens the separate page (not asked).

## Round 11 – comic outline & neumorphic skins

The planner now reads the same theme extensions as the home page
(`ComicOutline`, `NeumorphicSkin`) through one small helper,
`lib/planner/planner_skin.dart` (`PlannerSkin.of(context)`). With neither
skin it returns its input, so the default look is unchanged. Dialogs, menus,
chips, buttons, snackbars, date picker were already themed globally.

| Part | Comic outline | Neumorphic |
| --- | --- | --- |
| Tasks｜Schedule switch | 2dp outlined track and selected tab | sunk track, raised selected tab |
| Schedule block, handles | 2dp edge (3dp selected), no shadow | small shadow pair, no outline |
| Selection bar, 今 button | outlined pill / disc | raised pill / disc, accent number |
| Date strip day, week node | outlined filled circle | chosen/today sunk with accent number, others raised |
| Timeline & week lines | softened edge colour (ink is too heavy for a hairline) | unchanged |
| Task pool | outlined top edge, outlined cards and board tag | shadowed sheet, sunk cards and tag |

Dark mode uses each skin's dark palette; tests render day, selected block,
editor, expanded pool and week in 3 skins × light/dark at 400 and 360 wide.
Not verified: real-device look of the shadows/outlines.

### Round 11b – device feedback on the two skins

- Neumorphic title field in the schedule dialog: the theme's 26dp top band (for a floating label) pushed the placeholder up. Neumorphic now shows the title as a hint with equal top/bottom padding and centred text.
- Neumorphic pool cards are separate raised cards (home shadow pair) with 16dp side / 5dp top-bottom room, so nothing is clipped and cards sit ~10dp apart. Comic pool cards keep their outline with 12dp side / 3dp gap room. The pool's "Add" button no longer uses the theme's 16dp shadow gutter (it squeezed the label): same quiet-button-on-`NeuPressable` pattern as the home bar.
- Add panel: mode chip reads "Batch add / 批量新建 / 一括追加" (new key `batchModeShort`; the long text stays on the submit button), 8dp between hint and field, multi-line box 2–4 lines, comic text inset 16dp.
- Tasks｜Schedule switch, neumorphic: the selected tab uses one downward shadow instead of the light/dark pair, so both ends look the same.
- Home task rows: neumorphic card gap 32dp → 10dp. Comic rows lose the per-task thick box: 12dp side inset and a thin separator; a selected row keeps an outlined tint.
- Not verified on a device: the visual feel of all of the above.

## Round 12 – Windows / desktop pass

Desktop = Windows/macOS/Linux theme platform (`PlatformUiPolicy.isDesktop`). Phones are unchanged.

| Found | Fix |
| --- | --- |
| Schedule guide: content stuck to the top of a fixed 420dp card | Each step centred in its page; card 440×360 max, centred |
| Windows test toast showed the text twice | Body was sent both as the toast text and as `subtitle`; subtitle dropped. A second click while sending is ignored |
| "Check permissions" on Windows/desktop (cannot answer) | Shown on Android/iOS only; the test button takes the full row |
| Tutorial / settings stretch across a wide window | Tutorial capped at 680dp, settings list at 720dp, centred |
| Pool as a bottom sheet on a big window | ≥900dp desktop: fixed 340dp side panel; narrower windows keep the sheet |
| Round 今 button and swipe-only day change | Desktop toolbar always has ◀ ▶ and "Today" (disabled when already there); 今 button phone-only |
| No keyboard | ←/→ day or week, T today, D/W view, Delete (with confirmation), Esc clear selection, Ctrl+N new |
| Long press needed to drag with a mouse | Mouse press-and-drag moves blocks, week labels and pool cards; touch still long-presses |
| No mouse affordances | Hover tint + hand cursor on blocks and pool cards; right click a block → Edit / Delete; double click empty grid → new item at that quarter hour (mouse only) |
| Task detail as a phone bottom sheet on desktop | Centred dialog, ≤560dp wide |

Already right on desktop and left alone: add-task panel is a dialog; scrollbars come from Flutter's desktop scroll behaviour; `VisualDensity.adaptivePlatformDensity` is compact on desktop.

Suggestions (not done): multi-column settings on very wide windows; Shift+wheel to change day; a desktop-specific home layout review.
Not verified on a real Windows machine: feel of hover, drag, shortcuts and the toast.

## Linux 桌面实机运行（Round 14）

在 Linux（X11，1400×950 窗口）上 `flutter build linux` 后实机操作，发现并处理：

- 侧栏任务池的象限标签按四等分宽度排布，「Important · Urgent」被整体缩成很小的字，且彩色圆点压在文字上 → 标签宽度按文字所需分配（多余空间均分，不够才等比缩小），圆点槽位不随缩放，下划线跟随实际标签中心；侧栏宽 340→400。
- 侧栏里仍显示「左右滑动切换象限」提示（桌面无此手势）→ 侧栏模式不显示。
- 日程引导第 1/2/4/6 页写的是触屏操作（底部任务池、长按、双指）→ 桌面使用鼠标/键盘版文案（中英日）。
- 引导对话框按 Esc 无反应 → Esc 等同「跳过」。
- 切到日程页、关闭引导后键盘快捷键（←/→/T/D/W）不生效，必须先点一下页面 → 日程页激活、引导关闭、在页面内按下鼠标时把焦点收回快捷键节点（正在输入时不抢焦点）。
- 设置里「准时提醒与保活指南（Android 电池优化）」在 Linux/macOS 也显示 → 桌面隐藏（Windows 仍是自己的托盘指南）。
- 测试通知成功提示在非 Windows 平台写着「请查看 Windows 通知中心」→ 非 Windows 使用通用文案「请查看系统通知」。

## Round 15（桌面细节）

- 漫画描边：桌面「更多」对话框里的面板是直角，圆角描边外露出底色 → 漫画/拟态下对话框按自身圆角裁切（默认主题不变）。日程页 ☰ 菜单、右键菜单本就是主题的圆角 PopupMenu，实机确认无此问题。
- 桌面顶栏「今天 / 日 / 周」被 Flexible 平分到中间 → 改为普通子项，靠时间线区右侧（侧栏左侧，留页边距）。
- 桌面侧栏任务池左边缘可拖动调宽（悬停左右箭头光标），280 ~ min(560, 窗口一半)，宽度存 SharedPreferences。
- 漫画/拟态下「日 / 周」改为分段控件（凹槽/描边轨道 + 选中项凸起/描边，做法同顶部任务|日程切换条）；默认主题仍为原来的 ChoiceChip。「今天」沿用主题 TextButton（拟态本身即凸起）。
