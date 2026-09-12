# ADR：Flutter 为唯一主力客户端，React 冻结保留（已采纳）

日期：2026-09-09。状态：**已采纳；本轮已完成计划和派单文档切换。** 执行范围以 [Implementation Plan](IMPLEMENTATION_PLAN_2026-09-08.md) 和 [HANDOFF](HANDOFF.md) 为准。WP20-W 取消，下一包 WP21-N；没有移动/删除客户端文件，没有创建 UI 分支，功能包尚待实施。

## 1. 推荐结论

将持续开发集中在 `matrixflow-native/`，正式客户端目标先定 Android + Windows。一份 Dart 业务模型、状态、AI 服务与主要 UI，按手机/桌面适配布局和操作。React 待办停止追求新功能对齐，保留最后可用版本和迁移出口；其 Tauri / Capacitor 壳一起停止新功能投入。未来若重新需要浏览器待办，优先单独评估 Flutter Web，不立即维护第三个目标。

这比继续双轨更符合当前个人开发、额度有限、重视手机实机和桌面应用的约束。代价是 React 浏览器版不能继续作为最新功能入口。GitHub 展示和应用下载仍可用简单介绍页与录屏，不需要为介绍网站维护第二套完整待办应用。

此前双轨计划沿用用户当时的 Web + Flutter 目标。用户现已要求切换计划：保留功能需求，削减重复客户端实现。

## 2. 当前工程证据与边界

- 当前本地 `main` 为 `747eb35`，WP20-N 已完成、74 项测试通过。用户最新澄清：WP20-W 尚未开工，实施助手已暂停；此前“已改好”的说法被此澄清替代。现取消 WP20-W，下一包 WP21-N，无需等待不存在的 Web 成果汇入。
- `matrixflow-native/windows/` 已存在，文档记录 Windows release 曾通过。此轮未重跑构建；Windows 不是需要从零移植的新平台。
- `lib/screens/matrix_screen.dart:83` 已有 LayoutBuilder，宽度达到 900 时切为侧边输入区域+矩阵；仍需完善窄窗口、键盘、焦点和详情布局，不能把能编译等同于桌面体验完成。
- `lib/models.dart`、`storage.dart`、`ai_service.dart` 已承载 Flutter 数据、状态和 AI。后续不用再在 React `types.ts` / `App.tsx` / `services/aiService.ts` 复制同一功能。
- `lib/theme.dart:28` 使用 Material 3，卡片 elevation=0；这是已有实现选择。`index.html:90–138` 的 Web 拟态样式主要为亮暗双向外阴影、内阴影和按压位移，可在 Flutter 独立实现。
- `lib/screens/settings_screen.dart` 依赖 `dart:io`、原生文件选择和文件写入。因此即使 Flutter 支持 Web，也不能宣称现工程不改代码就能完整替代浏览器版。

Flutter 官方支持原生 Windows 桌面构建；桌面输入、焦点与辅助功能仍需适配。[桌面支持](https://docs.flutter.dev/platform-integration/desktop)、[输入与无障碍](https://docs.flutter.dev/ui/adaptive-responsive/input)

## 3. 方案取舍

| 方案 | 好处 | 当前代价 | 建议 |
|---|---|---|---|
| React + Flutter 持续对齐 | 保留成熟浏览器路径和原 Web 样式 | 模型、行为、日期、导入和测试重复演进；功能漂移风险持续 | 不再作为主路线 |
| Flutter Android + Windows 主力，React 冻结 | 业务和 UI 大量复用；沿用现有原生工程 | 仍要分别验收两个平台；网页端不再同步新增能力 | 推荐 |
| 立即同时发布 Flutter Android + Windows + Web | 长期可共享代码、保留浏览器入口 | 文件/插件、浏览器限制、输入与首屏等增加当前验收范围 | 浏览器需求再次明确时另做可行性包 |

这是减少重复实现，不是消除平台差异，也不保证工时或额度恰好减半。通知、托盘、全局快捷键、文件访问等保留平台适配层；测试仍覆盖 Android 与 Windows。业务规则不能在两个屏幕里各写一份。

Flutter Web 适合交互应用，但有浏览器文件访问与 SEO 等边界；官网和下载页可继续用普通 HTML。当前不以重做 Flutter Web 代替收缩范围。[Flutter Web FAQ](https://docs.flutter.dev/platform-integration/web/faq)

## 4. 已执行的文档切换与后续约束

本轮已将本节决策写入 Implementation Plan、HANDOFF、AGENTS、README 及架构/开发指南。应用功能继续按小包实施；兼容测试与发布固定版本在各自包执行，不把文档切换写成已完成迁移或发行。

1. **固定旧版与保留迁移路径。** WP20-W 未实施；已有旧版源码与依赖留在当前仓库，当前基线为 `747eb35`，构建命令保留在开发指南。本轮不新增标签或构建产物。将 React 标为 legacy / 维护冻结，不删除源码或用户数据，不归档整个 MatrixFlow 仓库。没有部署事实时不声称已保留在线服务。只有可能影响已发布用户的数据/安全问题再单独处理，不继续功能对齐。
2. **改派单与文档。** 更新 AGENTS、HANDOFF、Implementation Plan、README 的主入口和平台表。未实施的 `-W` 在当前计划中特指 React Web，应标“因客户端收敛取消”，不能改名假称为 Windows 已完成；对应需求仍由 Flutter 实现。`-N` 表示共享 Flutter 实现，必要时再分 Android / Windows 平台验收。WP21、WP03、WP04、WP23、WP12-S 等保留原需求，后续只实施 Flutter。WP28/29 的正式客户端先为 Android/Windows，介绍页与托管后端属于不同职责。
3. **保留数据兼容与验证。** 新 Flutter 继续读取旧 ExportData v1；使用无密钥旧版 fixtures 验证 boards、父子任务、完成、日期和配置导入。新字段按 WP11 的迁移契约演进，不再要求冻结的旧 Web 理解未来字段。若提供 v1 降级导出，提示不能保留的新字段。新版本回写旧 Web 不是默认支持承诺。Android/Windows 文件格式一致，不意味着自动跨设备同步，WP18 仍是独立功能。

无需现在把根目录 React 文件移动到 `legacy/`：目录搬动会牵涉配置和历史路径，不减少当前功能开发成本。先做到“不再给它派新功能”，以后真有整理需要再单独移动。

## 5. Windows 适配应跟随基础包进行

不要等所有手机功能完成后才发现 Windows 不能用。每个共享功能包附最小桌面检查：

- WP03 / WP04 / WP23：窗口缩放、矩阵/聚焦阅读、详情侧栏可用；小窗口回到全宽详情，不能把手机页面等比放大。
- WP12-S：键盘搜索、焦点返回、中文输入法、跨 board 定位正确。
- WP22：日期选择、保存和取消在鼠标/键盘操作下可发现。
- WP05 / WP24：鼠标拖放与可见菜单替代；不能把长按/横滑当作桌面唯一入口。
- WP26：命令面板、托盘、可选关闭到托盘和全局快捷键独立后补，不阻塞先把基础桌面完成/编辑做顺。

通用规则只在 Store/业务服务中实现一次，布局用同一任务数据和命令。新增插件时核对 Android/Windows 支持并分别构建；纯视觉小改不反复运行全量打包。

## 6. Flutter 可以做拟态，平面化不是能力限制

| 当前 Web 视觉 | Flutter 实现方向 |
|---|---|
| 凸起表面、亮暗双向外阴影 | BoxDecoration + 多个 BoxShadow |
| 内凹输入框、按下按钮 | 裁剪/自定义绘制封装内阴影；BoxShadow 本身不能直接等同 CSS inset |
| 微渐变、高光、圆角 | 渐变和边框/形状绘制 |
| 按压位移、阴影过渡、弹性动效 | 显式/隐式动画与 Transform，保持现有点击语义 |

Flutter 官方提供阴影列表和 CustomPainter 绘制能力，因此可以实现这些视觉方向；不承诺与 CSS 逐像素一致。先用框架能力做少数可复用表面/按钮，再按需要评估依赖，避免让主题包绑住业务。[BoxDecoration.boxShadow](https://api.flutter.dev/flutter/painting/BoxDecoration/boxShadow.html)、[CustomPainter](https://api.flutter.dev/flutter/rendering/CustomPainter-class.html)

这里真正需要控制的是信息密度、文字/控件可辨认性和滚动性能。无框十字矩阵可以搭配轻拟态工具栏、输入区和主按钮，没必要给每条任务、子项再套一层凸起大框。完成、多选、禁用、焦点不能只靠很浅的阴影区分。

大面积反复裁剪、模糊和离屏绘制可能影响帧耗时；应在 profile 模式下观察实际设备，而非看到 debug 卡顿就断言 Flutter 做不到。[官方性能建议](https://docs.flutter.dev/perf/best-practices)

## 7. 先基础闭环，再短期“UI 实验版”

同意用户提出的顺序。推荐基线包含：WP20-N（已完成）→ WP21 Flutter → WP03 Flutter → WP04 Flutter → WP23 Flutter → WP12-S Flutter → WP22-A/B Flutter。连同相应 Windows 基础检查后固定版本；不必等 Planner、同步、收费后台全部完成才试 UI。

届时从同一已验收提交创建用户所说的 **`UI实验版`** 分支；此轮没有创建。该分支是短期试验，不演变为第二条永久产品线。

1. **先只改视觉。** 封装主题 token/表面/按钮样式，保持同一 Store、Task 模型、手势与信息布局；若后续要改交互密度或控件位置，单独记录一个变量，不同时翻新全部流程。稳定版仍正常维护，必要 Bug 修复带到实验分支，比较前统一功能基线。
2. **自己就能比较。** 使用相同的合成多板任务，分别体验添加、勾完成、展开子项、编辑、搜索、切象限、长列表滚动。对比 360–412 dp 手机、窄/宽 Windows、浅深色和大字体；记录误触、正文可见量、操作步骤和帧时间。60 Hz 下以 UI/raster 各阶段约 16.7 ms 预算观察掉帧，120 Hz 对应约 8.3 ms；这是目标，不是未测承诺。无需招募几十人，截图只能判断外观，不能替代交互与性能试用。
3. **结束时收回一条主线。** 采用更合适的方案并合回 main，记录结论后结束试验分支；如两种皮肤都保留，尽量作为同一程序主题选项共享业务，而不是发布两套长期不一致的应用。实验包使用独立测试数据或实验应用标识，不拿真实待办做破坏性比较。

## 8. 当前交付范围

此前完成结构/样式与官方能力核对；本轮按用户要求将决策设为已采纳，并更新全部活动计划、交接提示词与项目规则。下一实施包明确为 WP21-N，结束交接 WP03-N。未改 React/Flutter 应用代码，未移动/删除文件，未建分支/标签，未重跑应用测试，未实现拟态。第 7 节实验方案已纳入计划第 10 节，无需助手只读 ADR 自行推导任务。
