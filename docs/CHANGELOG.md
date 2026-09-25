# 更新日志

## 2026-09-26 · RF03 凭据保存与退出协调（独立分支待集成）

- 快速修改或清空 API 凭据时按最后一次用户意图写入保护存储，旧写入完成不再覆盖新草稿；失败与读回失败可见并可重试。
- 退出保存等待普通数据、凭据和导入相关写入完成，失败与超时沿既有选择流程处理；显式含凭据导出也等待最新写入。新增合成凭据及重启回归，Android/Windows 新路径人工验收仍待 RF10。

## 2026-09-26 · RF02/RF05/RF07 返修集成

- 导入与普通命令共用 Store 串行提交顺序；提交时根据隔离的预览内容和活库重算，失败回滚保留提交期间已接受的修改。
- AI 连接与显式确认的生成测试统一管理取消、忙碌状态和结果归属，配置变化或迟到回复不再让按钮永久禁用。
- 输入法组字结束后的折叠范围可正常提交；未添加的子项输入计入草稿，保存时生成子项，关闭或切换任务时先询问。
- 上述改动已纳入默认回归；新增路径的 Android/Windows 设备验收仍待 RF10，凭据一致性、备份大小及模型能力仍由 RF03/RF04/RF06 继续返修。

## 2026-09-25 · 修复 Android Release 图标缺字

- Android Release 构建关闭 Material 图标字库裁剪，修复设备上图标显示为空框的问题。字库资源增大约 1.6 MB，APK 压缩后实测增大约 0.6 MB；Debug/Profile 构建不受影响。

## 2026-09-25 · OS27 公开文档与三语文案

- README、开发指南、架构、文档索引、贡献与安全说明对齐当前 Flutter Android/Windows 主线；明确源码、测试构建与稳定发行状态。
- 英中日引导和 AI 提示说明任务文本会发送到用户配置的端点，删除绝对隐私与通用无损承诺；托盘文案从字典读取并随语言设置更新。
- 隐私说明、商店物料和 v1.0.0 发行说明改为准确的候选/草稿状态，纠正系统凭据与明文备份说明。Windows 隔离运行证据、Android 未测与 OS26 待决门槛见 HANDOFF。

## 2026-09-25 · OS21/OS22 编辑会话与长列表

- 详情、子项和日期编辑共用有明确释放规则的会话；中文等输入法组字期间不会误提交。搜索与完成页采用与主界面相同的详情宽度断点。
- 设置中的模型请求、连接测试与备份流程拆成独立协调组件；页面关闭后不继续发起导出选择，也不回调已释放的输入框。
- 列表视图按可见窗口惰性构建。Windows 合成 1 万任务 profile 对照从约 2500 张挂载卡片降到 24 张；Android 帧表现未测，详见 HANDOFF。

## 2026-09-25 · OS18/OS20/OS23 字号、命令与减少动画

- 设置字号预览只缩放一次；逐行删除线按系统缩放重新测量，临时文本测量资源及时释放。
- 任务移动、紧急模式重置和截止日期自动提升更新修订号，避免旧撤销覆盖新编辑；设置页通过配置草稿提交 AI 设置，Store 支持独立快照和注入的保存/提醒服务。
- 入场、引导、自动回顶和布局动效统一读取时长策略；运行中开启减少动画会到达正确终态，手动滚动位置保持。双端人工观感和输入验收仍待做，见 HANDOFF。

## 2026-09-25 · OS16/OS19/OS26 单实例、可访问控件与发行门槛

- Windows 在任务库启动前限制同一用户只有一个进程，后续启动经命名管道唤起原窗口并转发通知参数；转发失败时不另开任务库。
- 父子任务复选框、子任务展开和设置中的小控件扩至至少 48dp 命中区，补齐语义标签、状态及键盘焦点，保留原有视觉尺寸。
- 发行脚本及工作流验证版本、Android 正式签名和精确产物清单；Windows 未签名状态明确披露。正式签名、托管发布和升级实机验收仍待完成，见 `docs/OS26_NOTES.md`。

## 2026-09-25 · OS15/OS17/OS25 退出、提醒与无密钥检查

- Windows 窗口关闭与托盘退出合并为幂等协调路径：先处理草稿，再等待保存结果；失败或超时由用户明确选择重试、不保存退出或取消。原生销毁失败可重试；隔离 Windows Debug 测试实例已验证协调完成后进程自行退出。
- 提醒权限未知不再误报已授权；排程与取消失败分别提示并进入有界本地重试账本，重启按当前任务数据补偿。测试提醒按实际结果反馈。Windows 隔离 smoke 已验证即时通知，未来定时排程与 Android 真机仍未验收。
- 新增固定 Flutter 3.32.8 的无密钥 PR/push 分析、测试及 Android/Windows debug 检查；更新隔离的 mock 集成测试和手动 Windows 通知/托盘 smoke。正式 release 缺签名时拒绝发布。GitHub 托管 runner 尚未执行；验证细节见 `docs/HANDOFF.md`。

## 2026-09-24 · OS24 固定 Flutter 3.32.8 工具链

- 已验证工具链固定为 Flutter 3.32.8 stable / Dart 3.8.1（framework `edada7c56edf4a183c1735310e123c7f923584f1`，engine `ef0cd000916d64fa0c5d09cc809fa7ad244a5767`）。CI release workflow、README、开发指南和打包脚本使用该版本。没有顺带升级依赖。
- `D:\Dev_SDKs\Flutter_SDK`（Flutter 3.31.0-1.0.pre.88 / Dart 3.8.0-197.0.dev）保持原样，作为回退。`pubspec.yaml` 的 Dart 下限仍包含该 dev 版本。
- 验收命令和平台结果见 `docs/HANDOFF.md`。Android 无连接设备，未做实机。

## 2026-09-24 · OS14 Windows 托盘与热键真实状态

- 托盘初始化、全局热键注册/注销和窗口隐藏使用可等待结果；托盘不可用时不关闭到无法召回的后台窗口，热键冲突和失败可见并可重试。启动、设置修改和设置导入共用运行态设置应用路径，迟到的旧结果不覆盖当前设置。
- Windows runner 直接检查系统热键注册结果，修正旧插件把冲突误报为成功的问题；设置页可更改快捷键。独立 Debug 测试窗口的隐藏/召回、保留快捷键冲突及重试通过。自动化与平台证据见 `docs/HANDOFF.md`；OS15 退出保存协调未包含在本包。

## 2026-09-23 · OS13 退场与隐藏象限焦点隔离

- 退场任务行和动画中不可操作的象限子树排除键盘焦点；焦点移到外层可见作用域，恢复后可再次遍历但不自动抢回焦点。常驻象限树和原滚动状态保持。
- OS-R07 原探针修前失败、修后通过；新增键盘、触摸和快速切换回归。设备级输入仍待验证，数量见 `docs/HANDOFF.md`。

## 2026-09-23 · OS12 日期提醒范围与本地日历

- 新建、父详情和子项的日期/提醒选择器使用同一范围和初值。截止日期可选到 2200-12-31；提醒可选从今天起的五个日历年。已保存的远期截止日期保持原值，选择器只在打开时使用窗口内的初值。
- “明天”和“本周”按本地年月日计算。提醒时间仍是一次性的绝对时刻。
- OS-R06 修前失败、修后通过。Android 无连接设备，Windows 应用未启动。数量见 `docs/HANDOFF.md`。
## 2026-09-23 · OS10/OS11 模型发现身份与协议连接测试

- 模型发现缓存改为 provider、规范化地址、协议和凭据。协议、地址或密钥变化会立刻作废旧列表；相同身份可复用，显式刷新会绕过缓存，页面关闭后不再更新界面。诊断不记录密钥。
- 普通 OpenAI 兼容请求默认只发送兼容字段。思考扩展按 DeepSeek、Responses 和 Anthropic 的模型能力附加。连接测试分开显示端点/鉴权、模型发现和所选模型生成；生成测试可能计费，必须由用户确认，启动和失焦不会自动发送。
- 验收使用合成数据和 HTTP mock。真实厂商调用以及 Android/Windows 实机本轮未测。数量见 `docs/HANDOFF.md`。

## 2026-09-23 · OS08/OS09 备份密钥选择与本机凭据保护

- 默认 v1/v2 JSON 导出省略 `customApiKey`；每次显式包含凭据先提示明文风险，并从系统凭据入口读取。旧含凭据备份仍可读，覆盖导入默认保留本机凭据，明确选择后才替换。
- Flutter Android/Windows 将 BYOK 凭据从普通配置分离。升级先写入系统保护存储并读回，再清理 OS06 双保存槽与旧配置镜像中的明文；失败保留恢复与重试入口。Android 最低 API 23，关闭自动备份及设备转移的应用数据。
- 合成数据专项、全量测试和平台验证结果记录在 `docs/HANDOFF.md`；Android 系统级读写需连接设备另行验收。

## 2026-09-23 · OS06/OS07 保存批次与导入事务

- 本机保存加入双槽完整快照、校验与提交指针；写入失败可观察并可重试，成功重试清除错误。启动优先读取已提交批次，旧核心键继续作为兼容镜像。SharedPreferences 返回成功不等于掉电持久化。
- JSON 导入增加 4 MiB、深度和记录数限值；预检 v1/v2、损坏与未知版本、板/任务/同父子项 ID、孤儿和空备份。设置页预览新增、跳过、冲突、修复、警告及覆盖影响；用户确认后先保存完整批次，再更新内存，失败保留旧库。OS-R02 修前复现、修后通过。
- 普通导出包含 API 密钥的既有行为未变；默认排除与凭据导入选择留 OS08。本轮未做 Android/Windows 新包实机及强杀/掉电验证。
- OS06/07 专项 12/12、OS-R02 原探针 1/1，默认全量 `flutter test --no-pub` 390/390、`flutter analyze --no-pub` 0 issues。

## 2026-09-23 · OS05 启动损坏数据保留与恢复

- 启动时若本机数据损坏或局部记录无法解析，保留原始存储值并暂停自动写回；恢复页面提供原始值副本保存和二次确认后丢弃损坏值的操作，取消及重启不清除源数据。
- 恢复副本可能包含 API 密钥，属于专用恢复文件，不是普通 JSON 备份。跨键保存失败和崩溃恢复仍留 OS06。
- OS-R01 修前复现、修后转绿；OS05 专项 7/7、默认全量 378/378、analyze 0 issues。未做 Android/Windows 实机或新构建。

## 2026-09-23 · OS03 DeepSeek 默认与配置归一化

- 新安装的 DeepSeek 默认模型改为 `deepseek-flash`；明确的旧 DeepSeek 预设默认名在加载时迁移，自定义模型原样保留。
- 未知提供商回退为自定义并保留 URL/模型；空模型按预设缺省处理，无法确定时在请求前提示填写。设置提示与三语推荐文案同步更新。
- OS-R03/05 修前复现、修后转绿；OS03 专项 9/9、默认全量 371/371、analyze 0 issues。真实 AI 服务及 Android/Windows 设备调用本轮未测。

## 2026-09-22 · OS02 父子任务视觉层级

- 新增共享父子视觉策略：父/子标题分别 16/14dp，复选框实际绘制分别 22/18dp，两者命中区均为 48×48dp。
- 主任务卡、搜索结果、详情子项与已完成页统一该层级；矩阵同列和聚焦/列表 16dp 子项缩进保持不变。
- OS02 专项与相邻 UX03/UX05 回归 16/16、默认全量 362/362、analyze 0 issues；本包未新增双端实机验收。

## 2026-09-22 · OS01 清除 Flutter 空状态斜体

- 矩阵空状态与列表空状态统一使用正常字形，移除两处显式 `FontStyle.italic`。
- 保持原字号、颜色、布局和用户任务内容不变；本包不改冻结的 Web/Tauri/Capacitor。

## 2026-09-20 · 列表退出中切换视图不再卡住

- 宫格/列表切换在聚焦中和淡出中都会结束焦点会话，不再把 `_listExitFading` 留在无动画状态。
- Windows Escape 与系统返回一样能强制结束列表退出。
- 定向 S1 与复审探针 7/7、全量 359/359、analyze 0 issues；双端实机未验。下一包 UX08。

## 2026-09-19 · 列表聚焦退出与退场缓存交叉修复

- 列表模式退出淡出可被重新聚焦打断并恢复透明度；Windows 打开侧栏不再丢掉退出完成；减少动画退出改为帧后通知，避免构建期 setState。
- 象限 Stack 子节点使用稳定区域键，进入非 Q1 不再拆掉其他象限的完成退场状态。
- 退场缓存以当前查询顺序为准，只把离场快照插回原位。
- 定向 6/6、全量 358/358、analyze 0 issues；双端实机未验。详情见 [状态交叉修复](UX_STATE_FIX_2026-09-19.md)，下一包 UX08。

## 2026-09-18 · UX07 象限连续聚焦几何动画

- 四个象限常驻同一有界 Stack，矩阵↔聚焦只做矩形插值：所选象限从自身格子连续扩大为主区，其余三格同步收拢为下方卡片；进入 320ms / 切换 300ms / 退出 280ms easeInOutCubic。
- 动画中返回、点另一张卡片、缩窗、切板、切视图模式都按当前几何重定向，不回首帧；减少动画一帧终态；过渡中任务行惰性、卡片可点击重定向、静止后恢复拖放。
- 卡片高度按三语标题实量，窄宽改三行；删除替树式聚焦视图，滚动/展开/划线状态全程存活。
- 列表模式进入聚焦用轻量淡入叠层，退出淡出后回列表原滚动位置；聚焦中切视图模式先退聚焦。
- 定向 10/10、全量 352/352、analyze 0 issues；双端实机未验。已随 UX06 一并提交 `eee6df9`。详情见 [UX07 返修记录](UX07_FIX_2026-09-18.md)，下一包 UX08。

## 2026-09-18 · UX06 完成划线动画、减少动画与安全退场

- 完成划线改为可中断、可反向的逐行动画：行段取自 `TextPainter` 实际字形/省略后的显示区域，220ms easeOut；初次加载已完成任务直接终态。
- 新增 `reduceMotion` 设置（默认关，v2 持久化、v1 降级剥离）：应用设置与系统减少动画取 OR，`StaggerIn`、划线、退场、滑动均立即到终态，任务仍立即保存。
- hideCompleted/筛选导致行消失时先保留展示快照再收拢退场；删除、清板、导入、切板、销毁立即清理，计时回调不写回任务。
- 完成入口收敛为一次点击一次业务写入（复选框热区不再与行点击叠加）。
- 定向 14/14、全量 342/342、analyze 0 issues；双端实机未验。已与 UX07 一并提交 `eee6df9`。详情见 [UX06 返修记录](UX06_FIX_2026-09-18.md)。

## 2026-09-17 · UX05 矩阵父子同行对齐

- 矩阵父子标题与复选框列同列；聚焦/列表/详情子项缩进 16dp。矩阵去掉内嵌添加子项，详情保留。
- 定向 4/4、全量 328/328、analyze 0 issues；双端实机未验。详情见 [UX05 返修记录](UX05_FIX_2026-09-17.md)，下一包 UX06。

## 2026-09-17 · UX04 Windows 中文字体与预览

- Windows 黑体用 Microsoft YaHei UI，系统/等宽带 CJK 回退；Android 不写 Windows 字体名。
- 设置预览含中英日混合样句与标题/正文字重；等宽说明 CJK 会回退。界面标题不再用 w800 冒充粗体。
- 定向 3/3、全量 324/324、analyze 0 issues；DPI/IME 实机未验。详情见 [UX04 返修记录](UX04_FIX_2026-09-17.md)，下一包 UX05。

## 2026-09-17 · 工作区收口：基础修复与 UX01–UX03 入库

- 分批提交：`c7902b1` 基础 F/SR 修复，`e509166` 复审文档，`3e166b4` UX01–UX03。工作区不再堆积未提交主线改动。
- 未发布、双端实机仍未验。下一包 UX04。

## 2026-09-17 · UX03 搜索与归档纵向筛选

- 去掉搜索/归档横滑 Chip；Android 底部纵向筛选、Windows 纵向面板；draft/apply/reset，清除筛选保留关键词。
- 查询口径不变；条件摘要换行并显示真实看板名；归档只有范围选择。
- 定向 9/9、全量 321/321、analyze 0 issues；双端实机未验、未发布。详情见 [UX03 返修记录](UX03_FIX_2026-09-17.md)，下一包 UX04。

## 2026-09-17 · UX02 双端导航、设置与可选完成率

- Android 底部三个动作、Windows 顶部三个动作；已完成/视图/显示完成/选择/设置归入更多；去掉 34dp 七按钮头与常驻左侧新建栏。
- 设置增加默认关闭的总体完成率，仅在首页更多面板显示；Windows 快捷键帮助进设置，Android 不展示 Ctrl/⌘。
- 定向 9/9、全量 312/312、analyze 0 issues；双端实机未验、未发布。详情见 [UX02 返修记录](UX02_FIX_2026-09-17.md)，下一包 UX03。

## 2026-09-17 · UX01 命令台与统计 UI 返修

- 删除双端命令台、Ctrl/Cmd+K、主页/聚焦统计条及归档完成率/趋势图；保留归档时间、恢复、删除、详情与有效快捷键。
- 归档计数明确为列表结果数，范围与时间支持窄屏换行；新手引导删除趋势承诺和模拟柱图。
- 定向 19/19、全量 302/302、analyze 0 issues；双端实机未验、未发布。详情见 [UX01 返修记录](UX01_FIX_2026-09-17.md)，下一包 UX02。

## 2026-09-16 · 基础二审返修（SR01–SR07）

- 提醒取消与排程共用有序队列，旧恢复遍历在清空/覆盖导入后失效；冷启动缓存通知载荷，首帧后定位父任务或子项一次。
- 搜索/已完成页返回保护草稿；缩窄窗口使用全宽详情并保留编辑状态；模型发现改用配置快照，Key/URL/协议/模型变更使旧响应失效。
- 子项完成热区扩至 48×48 dp，调整日期布局避免窄屏溢出；排程失败显示任务名与三语提示，提供重试，成功清错。
- 校正本地密钥、自定义 API 地址及明文备份的隐私说明。
- 默认测试 305/305、analyze 0 issues。双端构建及设备未验收边界见 [二审返修记录](FOUNDATION_SECOND_FIX_2026-09-16.md)，未发布。

## 2026-09-16 · 基础复审缺陷修复（F01–F22）

- **数据安全与详情编辑**：宽屏切任务不再把旧草稿写入新任务；保存时按字段合并，不覆盖外部完成/新增子项；损坏备份整份拒绝，不再静默覆盖清空；返回/Esc/切任务或任务板/尺寸变化保护未保存草稿；详情改象限走 Store 置顶与人工紧急性。
- **提醒生命周期**：首次设提醒会申请权限，拒绝仍保存并提示；按通知 ID 修订号处理排程/取消竞态；删除子项注销通知；初始化完成前的恢复会排队；Windows 原生排程成功则不再同时开 Timer；未来提醒排程失败不再立即弹出。
- **Windows 桌面接线**：接入 window_manager / tray_manager / hotkey_manager（关闭拦截、托盘菜单、恢复、退出、全局热键）。自动化只覆盖回调与策略，系统托盘/热键待干净 Windows 实测。
- **日常交互与统计**：完成时间只在真实状态转换时记录；编组保留 completedAt；父子统计独立；历史未知时间不伪造；后续任务操作会使旧撤销失效；模型发现取消后复位 loading；自定义协议显示思考开关；大字号聚焦卡不再固定 78dp 溢出；完成热区覆盖 48dp；命令面板组词时不把 Enter 当确认。
- **发行配置**：CI 正式发布缺签名必须失败；本地无 CI 仍可 debug 回退。旧 Android applicationId 迁移路线见 `docs/ANDROID_PACKAGE_MIGRATION.md`，不指导卸载旧版。未实际发布。
- **验证**：`flutter test --no-pub` 280 项；`flutter analyze --no-pub` 0 issues。探针 R01–R21 已迁入 `test/foundation_regression_test.dart`。



> 本项目在开发期间未维护变更日志。以下内容于 2026-08-30 依据 Git 提交历史（`git log`）与代码现状重建整理，格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)。
>
> 开发周期：2025-11-22 至 2025-11-25，共 7 个提交，均为 `main` 分支直线历史（无标签、无远端仓库）。
>
> 2026-09-03 起进入修复与打磨阶段，新增条目按日期追加在下方。

## 2026-09-16 · V1.0.0 开源首发全量闭环（WP28-R, WP28-B, WP28-P）

- **WP28-R 全平台开源合规与发行规划（docs/RELEASE_PLAN.md）**：
  - 确立客户端整体采用宽松 **MIT License**，全量排查第三方依赖库授权协议（BSD-3-Clause / MIT / Apache 2.0，全量 Permissive 兼容）；
  - 声明旧版 React 19 / Vite 原型冻结归档，不随新版发行；
  - 统一双端应用元数据与标识：App 展示名称为 MatrixFlow AI，Android 包名 `com.matrixflow.app`，Windows AUMID `MatrixFlow.MatrixFlowApp.1.0`，版本号统一为 SemVer `1.0.0+1`；
  - 设计本地开发、CI 构建与正式签名的安全隔离方案（Android `key.properties` / 环境变量隔离，杜绝私钥入库，本地优雅降级为 debug 签名）；
  - 整理全渠道发布矩阵（GitHub Release、酷安、小米、华为、Windows 便携包）上架资质与材料清单；
  - 确立 100% 纯本地优先、BYOK 直连服务商与零隐私侵入合规声明。
- **WP28-B Android 与 Windows Release 自动化构建打包与 CI（matrixflow-native/）**：
  - Android 打包配置：在 `android/app/build.gradle.kts` 中完善安全 release 签名逻辑（支持 `key.properties` 与环境变量读取、缺失时安全回退 debug 签名保证本地编译与 CI 顺畅）、开启核心库脱糖（`isCoreLibraryDesugaringEnabled = true`）并引入 `desugar_jdk_libs:2.1.4` 满足通知插件要求、配置 `applicationId = "com.matrixflow.app"` 与 `android:label="MatrixFlow AI"`；
  - Windows 桌面配置：更新 `windows/runner/Runner.rc` 元数据与产品名称为 `MatrixFlow AI`、更新 `main.cpp` 窗口标题为 `MatrixFlow AI`；
  - 版本号升级：`pubspec.yaml` 升级为 `1.0.0+1`；
  - 一键打包自动化脚本：新增纯 ASCII 跨平台 PowerShell 脚本 `scripts/build_release.ps1`，自动执行双端 Release 构建、解析版本、产出 `matrixflow-v1.0.0-android.apk`（24.6 MB）、`matrixflow-v1.0.0-windows-portable.zip`（12.0 MB），并生成 `SHA256SUMS.txt` 校验清单；
  - GitHub Actions 流水线：新增 `.github/workflows/release.yml`，支持 Tag（`v*`）触发自动构建双端产物并发布 GitHub Release。
- **WP28-P 开源首发物料、隐私政策与商店上架准备**：
  - 根目录新建 `LICENSE`（MIT 许可证，正式开源授权）；
  - 全面更新根目录 `README.md` 与 `matrixflow-native/README.md`（提供高质量中英双语架构图解、特性一览、BYOK 配置步骤、安全声明与编译打包指南）；
  - 新增正式中英双语隐私政策 `docs/PRIVACY_POLICY.md`（声明 100% 本地优先原则、BYOK 直连零中转、零数据追踪埋点、权限用途合规说明）；
  - 新增 GitHub Release 官方发布说明模板 `docs/release_notes/v1.0.0.md`；
  - 整理应用商店送审与权限说明文档 `docs/STORE_LISTING.md`（提供简短/详细中英介绍、图标与 5 张高清截图规范、权限用途合规答辩——明确通知必要性，严格不使用高危 `USE_EXACT_ALARM` 保障商店合规）。
- **验证与基线保持**：
  - 全量自动化测试：`flutter test --no-pub` 保持 **255/255** 全绿；
  - 静态代码分析：`flutter analyze --no-pub` 保持 **0 issues**；
  - 双端 Release 构建实测全部通过并完成打包。

## 2026-09-16 · WP09-N 首次引导教程与手势说明

- **5 页响应式引导教程与手势说明（lib/screens/onboarding_screen.dart）**：
  - 第 1 页：四象限法则与换行快速批量添加（介绍重要/紧急维度、换行批量导入待办）；
  - 第 2 页：长按拖拽与象限流转（拖拽移动、跨象限置顶、右键菜单替代）；
  - 第 3 页：任务详情、子任务清单与定时提醒（多行输入、独立子项日期与闹钟排程）；
  - 第 4 页：完成历史、趋势统计与 5 秒撤销（7 日完成柱状图、左滑删除/右滑完成、5 秒 SnackBar 撤销）；
  - 第 5 页：AI 智能助手与纯本地 BYOK 隐私（无说教拆解/分组、本地存储、直连服务商零数据上传）。
- **交互控制与键盘导航**：
  - 支持左右翻页（上一页 / 下一页）与右上角“跳过（Skip）”；
  - 桌面与无障碍键盘快捷导航支持（Escape / 左方向键 / 右方向键）；
  - 支持 `isReviewMode`（在设置页重温时不展示跳过按钮，完成时显示“完成浏览”）。
- **持久化首启已阅标记（lib/storage.dart）**：
  - 本地机器级存储键 `matrixflow-has-seen-onboarding`（`_kHasSeenOnboarding`），不混入待办备份与四键核心持久化数据，换机或导入时不影响新设备引导体验；
  - 首启未阅时在 `MatrixHome` 首帧后自动触发引导全屏弹窗；
  - 提供 `completeOnboarding()` 持久化与 `resetOnboardingForTest()` 测试桩。
- **设置页重温入口（lib/screens/settings_screen.dart & lib/l10n.dart）**：
  - 在设置页“帮助与关于”区域提供“使用引导与手势说明”（`reopen-onboarding-btn`），用户可随时以 `isReviewMode` 重新浏览教程与手势提示；
  - 完整补齐中、英、日三语本地化字典（`onboardingTitle`、`slide1Title`、`reopenOnboarding` 等）。
- **自动化测试与全量回归**：
  - 新增 `test/onboarding_test.dart`（5/5 全绿，覆盖首启自动弹出、跳过持久化、设置页重温、中英日多语言渲染与键盘 Esc 退出）；
  - `test/helpers.dart` 与 `test/widget_regression_test.dart` 补充默认 `hasSeenOnboarding: true` 测试桩，防止已有 Widget 拦截回归测试；
  - 全套测试：`flutter test --no-pub` **255/255** 全量通过，`flutter analyze --no-pub` **0 issues**。

## 2026-09-16 · WP27-B-N 完成历史与时间戳

- **完成时间戳模型扩展与持久化（lib/models.dart & lib/storage.dart）**：
  - `Task` 与 `SubTask` 增加可选 `completedAt`（`int?`，毫秒时间戳），未完成或还原时为 `null`；
  - 勾选完成状态转换时记录当前系统毫秒时间戳；编辑已完成任务保持原时间戳不变；取消完成或撤销恢复时清除为 `null`；
  - `TaskUndoSnapshot` 完整捕获并还原 `completedAt`，保证 5 秒撤销动作状态一致；
  - 遵循 WP11 数据迁移与降级契约：`ExportData v2` 完整持久化，`version: 1` 降级导出时安全剥离字段；旧数据读取安全回退 `null`，严禁借 `createdAt` 伪造完成时间。
- **纯统计聚合与 7 日完成直方图（lib/task_stats.dart & lib/screens/completed_screen.dart）**：
  - `computeCompletionHistoryStats` 纯函数计算模型，按本地日历天聚合最近 7 天完成数量分布（`DailyCompletionBucket`）；
  - 父子任务完成数严格独立统计，防止双重计数；历史无时间戳旧任务安全归入 `unknownDateCount`；
  - `CompletedScreen` 顶部新增“完成趋势”（`_buildTrendsCard`），提供 7 日微型直方图（Mini-Histogram）、今日完成、7 日累计与历史任务统计指标；
  - 列表项支持按完成时间倒序（降序）排序，并展示完成时间徽标（`_formatCompletionTime`：刚刚、MM-dd HH:mm 或 yyyy-MM-dd）。
- **自动化测试回归**：
  - `test/task_stats_test.dart` 与 `test/data_migration_test.dart` 补充完成时间戳聚合计算、跨天分桶、撤销恢复及 v1 剥离测试（新增 5 项测试，达 250/250）；
  - `analyze --no-pub` 0 issues。

## 2026-09-16 · WP25-N-Windows Windows 桌面端本地通知与托盘联动落地

- **Windows 本地通知初始化与配置（lib/services/reminder_service.dart）**：
  - `FlutterLocalNotificationsReminderService` 支持在 `defaultTargetPlatform == TargetPlatform.windows` 环境下实例化与初始化；
  - 配置 `WindowsInitializationSettings`（`appName: 'MatrixFlow AI'`、`appUserModelId: 'MatrixFlow.MatrixFlowApp.1.0'`、固定应用 GUID `69a03975-2989-4d05-b778-5e824707612f`）；
  - `WindowsNotificationDetails` 设置 `WindowsNotificationDuration.long`，并将备注或描述作为通知副标题（subtitle）展示；
  - 在 Windows 平台下，`checkPermission()` 与 `requestPermission()` 自动返回 `granted` 与 `true`，无需 Android 特有的运行时权限弹窗。
- **托盘联动与后台进程定时保活（lib/services/reminder_service.dart & lib/services/desktop_shell_service.dart）**：
  - 联动 WP26-B `DesktopShellService` 托盘机制：用户开启“最小化到托盘/关闭到托盘”后，主窗口隐藏，Flutter 进程在后台常驻运行；
  - `scheduleReminder` 在 Windows 环境维护应用内内存 `Timer`（`_activeTimers`），定时到达时直接触发本地通知弹窗，解决桌面离线调度问题；
  - 任务重排、更新、删除、取消或 `cancelAll` 时，同步清理并取消对应内存 `Timer`，杜绝内存泄漏与幽灵通知。
- **通知点击激活与深层路由（lib/main.dart & lib/screens/matrix_screen.dart & lib/services/reminder_service.dart）**：
  - 用户点击 Windows Toast 通知后，通过 `onDidReceiveNotificationResponse` 自动调用 `DesktopShellService.instance.restoreWindow()` 恢复主窗口显示；
  - 反序列化 `ReminderPayload` 并传递至 `MatrixHome`，跨看板时自动切换至目标 `boardId`，定位任务并展开对应子任务，最终打开 `TaskDetailPanel`；若任务已删除，弹出友好 SnackBar 提示而不会发生崩溃。
- **设置页 Windows 可靠性指南与测试通知（lib/screens/settings_screen.dart & lib/l10n.dart）**：
  - Windows 环境下自动呈现“Windows 提醒与通知可靠性指南”（`windows-reminder-guide-tile`），向用户说明 Windows 托盘常驻保活、专注助手（Focus Assist / 免打扰）以及操作中心通知历史设置；
  - 提供“发送测试通知”按钮（`test-windows-notif-btn`），方便用户在桌面即时校验 Windows Toast 通知通道是否畅通；
  - 完整补齐中、英、日三语本地化字典（`windowsReminderGuide`、`windowsGuideTrayTitle`、`windowsGuideFocusTitle`、`testNotification` 等）。
- **自动化测试与全量回归**：
  - `test/reminder_service_test.dart`（14/14 全绿，包含 Windows 平台权限、托盘窗口恢复联动与 NotificationDetails 配置测试）；
  - `test/windows_reminder_test.dart`（4/4 全绿，包含 Windows 权限与 Timer 调度、托盘最小化后点击 Toast 唤醒深层跳转、已删除任务安全提示、设置页指南弹窗与测试通知）；
  - `test/widget_regression_test.dart` 补充 Windows 平台设置页指南对话框与测试通知按钮回归测试；
  - 全套测试：`flutter test --no-pub` **245/245** 全量通过，`flutter analyze --no-pub` **0 issues**。真实 Windows 锁屏/免打扰 Action Center 横幅弹出写明未测实机。

## 2026-09-16 · WP25-N-Android Android 本地定时通知与提醒落地

- **系统权限声明与开机接收器（AndroidManifest.xml）**：
  - 声明 `POST_NOTIFICATIONS`（Android 13+ 通知权限）、`SCHEDULE_EXACT_ALARM`（精确闹钟排程）、`RECEIVE_BOOT_COMPLETED`（开机自动恢复排程）与 `VIBRATE`；
  - 严格遵循 Google Play 策略，未声明 `USE_EXACT_ALARM`，规避任务待办类应用上架违规驳回；
  - 配置 `ScheduledNotificationReceiver` 与 `ScheduledNotificationBootReceiver`，支持系统重启与电源管理恢复。
- **数据模型与存储演进（lib/models.dart & lib/storage.dart & docs/DATA_COMPATIBILITY.md）**：
  - `Task` 扩展 `reminderAt`（`int?`，毫秒时间戳）与 `reminderTimezone`（`String?`）；`SubTask` 扩展 `reminderAt`（`int?`）；
  - `AIAnalysisResult.toTask` 支持携带提醒时间，新建任务与 AI 输入快照无缝传递提醒；
  - 遵循 WP11-N 数据迁移与兼容契约：`ExportData v2` 导出完整序列化 `reminderAt` 与 `reminderTimezone`，`version: 1` 降级导出时安全剥离字段；`fromJson` 对缺失字段默认回退 `null`；
  - `Store` 生命周期联动：
    - `Store.init()` 启动时自动重新排程未来未完成提醒（`rescheduleAllFuture`）；
    - `addTasks` 自动为含未来 `reminderAt` 的任务排程；
    - `updateTask` 在任务勾选完成时自动注销提醒，未完成时根据 `reminderAt` 重排或取消；
    - `deleteTask` 与 `deleteTaskWithUndo` 级联取消父任务与所有子任务通知；
    - `applyUndo` 恢复删除时重新排程未完成提醒；
    - `clearBoard`、`clearQuadrant` 与 `deleteBoard` 批量取消关联看板所有通知；
    - `importData` 在覆盖导入时全量取消旧通知并重排新数据未来提醒，合并导入时排程新增提醒。
- **通知服务实现（lib/services/reminder_service.dart）**：
  - 31 位确定性 FNV-1a 哈希算法（`generateNotificationId`），为父任务与子任务分配无冲突的 31 位正整数 Notification ID；
  - `ReminderPayload` 结构化序列化与反序列化（`taskId`、`subtaskId`、`boardId`），支撑点击通知深度路由；
  - 实现 `ReminderService` 统一抽象接口，提供 `FlutterLocalNotificationsReminderService` 生产服务、`InMemoryReminderService` 测试服务与 `NoopReminderService` 桌面降级服务；
  - 具备防崩保护安全守卫（`_initialized` 检测），在未初始化或测试环境下安全静默，杜绝 `LateInitializationError`。
- **界面交互与引导（widgets/task_detail_panel.dart & widgets/input_sheet.dart & screens/settings_screen.dart & widgets/task_card.dart & lib/l10n.dart）**：
  - 详情面板增加提醒配置入口（`edit-reminder-btn`）与清除按钮（`clear-reminder-btn`），提供快速预设 Chip（截止日当天 09:00、今天 18:00、明天 09:00、自定义时间）；子任务支持独立提醒配置；
  - 新建弹层（`InputSheet`）增加可选提醒时间入口（`input-reminder-btn`），与截止日期互不干扰；
  - 设置页面增加“提醒可靠性指南”弹窗（`reminder-guide-tile`），向用户说明主流国产 ROM（小米 MIUI/HyperOS、华为 HarmonyOS、OPPO ColorOS、vivo OriginOS）后台保活与自启动设置，并提供“检查提醒与通知权限”（`check-permissions-btn`）实时状态检测；
  - 四象限卡片与子任务行增加激活提醒小闹钟角标（`Icons.notifications_active_outlined`）；
  - 完整支持中、英、日三语本地化字典。
- **自动化测试与验证**：
  - `test/models_test.dart`（23/23）、`test/reminder_service_test.dart`（11/11）、`test/deadline_policy_test.dart`（22/22）；
  - `test/widget_regression_test.dart` 补充 TaskDetailPanel 提醒设置、SettingsScreen 保活指南与权限检测、TaskCard 提醒角标显示测试；
  - 全套测试：`flutter test --no-pub` **237/237** 全量通过，`flutter analyze --no-pub` **0 issues**。未做 Android 物理实机验证，未改动 React Web。

## 2026-09-16 · WP25-R 本地提醒与通知规范与选型研究（技术契约与架构设计）

- **技术契约与规范建立（docs/REMINDERS_DESIGN.md & docs/DATA_COMPATIBILITY.md）**：
  - 产出《本地日期时间提醒与通知技术契约与架构设计规范》（`docs/REMINDERS_DESIGN.md`）；
  - 确立 100% 纯本地离线优先与无恶性常驻后台守护（No Rogue Daemon / No Sticky Foreground Service）设计原则；
  - 明确“截止日（`deadline`）/ 提醒时刻（`reminderAt`）/ 计划日（`plannedDate`）”三者正交解耦规范：设置截止日不强行开提醒，设置提醒不伪造截止日；
  - 确立父任务与子任务对等独立的可选 `reminderAt` 时间戳支持。
- **系统权限与平台机制梳理**：
  - Android 平台：梳理 `POST_NOTIFICATIONS` 运行时权限、`SCHEDULE_EXACT_ALARM` 精确闹钟权限及其降级机制（Inexact Window Alarm）、`RECEIVE_BOOT_COMPLETED` 开机广播恢复排程，以及规避 `USE_EXACT_ALARM` 上架违规红线；梳理小米/华为/OPPO/vivo 厂商后台限制与白名单引导策略；
  - Windows 平台：深度联动 WP26-B `DesktopShellService` 托盘机制，明确窗口可见、最小化到托盘（后台 Isolate 运行）与彻底退出三种生命周期，规范 WinRT Toast 通知与专注助手（Focus Assist）契约。
- **调度生命周期与统一 Dart 抽象**：
  - 设计 31 位无符号 FNV-1a 哈希算法，确保 String 任务 ID 与系统 32 位整型通知 ID 具备确定性映射；
  - 建立生命周期级联取消规则：任务完成即时取消通知、任务删除/清空看板批量注销、导入覆盖全量重建；
  - 确立开机与冷启动过期提醒抑制契约（首版不批量狂弹过期提醒，仅限 5 分钟内轻度近时唤起）；
  - 定义跨平台统一 Dart 接口 `ReminderService` 与 `ReminderPayload` 路由契约。
- **验证与基线保持**：
  - 全量回归：`flutter test --no-pub` **223/223** 全绿，`flutter analyze --no-pub` **0 issues**。

## 2026-09-15 · WP13-A-N Flutter 基础纯文本备注与搜索接入

- **数据模型与兼容演进（models.dart & storage.dart & docs/DATA_COMPATIBILITY.md）**：
  - `Task` 与 `SubTask` 均扩展可选 `notesMarkdown` 字符串字段，默认 `null`；
  - 遵循 WP11-N 数据迁移契约与版本规范：`ExportData v2` 导出完整序列化 `notesMarkdown`（当非空时），`version: 1` 降级导出时安全剥离字段，保证与旧版双向兼容互通；
  - 任务编组 `groupTasks` 在聚合为子任务时完整保留原任务与原有子任务的 `notesMarkdown`；`TaskUndoSnapshot` 撤销删除与还原完整保留备注内容。
- **任务详情面板与子项备注交互（widgets/task_detail_panel.dart & l10n.dart）**：
  - 标题与备注清晰分离：在任务详情面板标题输入框下方增加多行纯文本备注编辑器（`edit-notes`），Enter 换行、Ctrl+Enter 快捷保存；
  - 支持原样保存与清空：输入内容原样保存为纯文本，清空输入框保存自动置回 `null`，不生成多余空白占位；
  - 草稿脏检查与防丢保护：修改备注未保存时尝试关闭弹层，触发“放弃修改？”弹窗确认，点击“继续编辑”保留草稿，点击“放弃”安全回退；
  - 子任务独立备注：在子任务编辑弹窗中增加多行备注编辑框（`subtask-edit-notes`），并在详情面板子任务列表中展示备注摘要；
  - 中英日三语词条：补充 `notes`、`notesHint`、`subtaskNotes` 字典。
- **本地搜索接入（task_query.dart）**：
  - 关键字查询扩展：在 `queryTasks` 中将父任务与子任务的 `notesMarkdown` 纳入搜索匹配（支持中英日不区分大小写）；
  - 严格安全隔离：不复用历史 `reasoning`，搜索逻辑严格不匹配 `reasoning` 与 API 密钥；AI 服务不默认将备注作为 Prompt 发送。
- **测试与回归（test/models_test.dart & test/task_query_test.dart & test/widget_regression_test.dart）**：
  - 补充 Task/SubTask 备注 round-trip、v1 剥离与 v2 保留测试；
  - 补充父子备注中英日搜索命中与 reasoning 排除测试；
  - 补充详情面板备注编辑、保存、清空、放弃草稿保护与搜索定位 Widget 测试；
  - 验证：`flutter test --no-pub` **223/223**（全量通过，新增 4 项测试），`analyze --no-pub` **0 issues**。未做 Android/Windows 实机，未改 React。

## 2026-09-15 · WP22-C-N Flutter 截止日期自动调整紧急性算法统一与人工覆盖

- **日历天统一算法与策略模块（deadline_policy.dart & task_query.dart）**：
  - 新建 `deadline_policy.dart`，抽取统一 `calendarDaysLeft(int deadlineMs, {DateTime? now})`：基于本地时区午夜对齐（`DateTime.utc(year, month, day)` 差值计算），杜绝夏令时（DST 23/25 小时）与当天时刻差异波动，精准统一定义 0 为当天、1 为明天、负数为过期。
  - 判定与升级契约 `isDeadlineUrgent`、`promoteToUrgent`：明确“提前 N 天转为紧急（含当天，即 `daysLeft <= thresholdDays`）仅作用于有截止日期的未完成主任务”，过期仍算紧急；无日期任务、子任务及已完成任务绝对不移动；仅允许 Q2→Q1、Q4→Q3，保持重要性不变，严防反向降级。
  - 重构 `task_query.dart` 导出策略函数，并在 `widgets/task_card.dart` 中彻底移除 `_DeadlineChip` 内部硬编码 `daysLeft <= 2` 的逻辑，统一接入 `isDeadlineUrgent(deadline, thresholdDays)`，消除界面标签视觉与后台自动升级阈值脱节问题。
- **人工覆盖模式与数据兼容演进（models.dart & storage.dart）**：
  - 任务模型扩展 `UrgencyMode` 枚举（`auto` 自动 / `manual` 人工覆盖），默认 `UrgencyMode.auto`；旧版或缺失数据健壮兜底为 `auto`；遵循 WP11-N 数据演进契约，`ExportData v2` 完整持久化 `urgencyMode`，`version: 1` 降级导出时安全剥离字段，保持与旧版双向兼容；保持本地核心四键不变。
  - 显式拖拽与详情修改感知：用户显式跨越紧急维度（Q1↔Q2, Q3↔Q4）移动或修改象限时置为 `manual`；仅改重要性（Q1↔Q3, Q2↔Q4）不改变模式；修改或清除截止日期保留用户的 `manual` 意图，不暗自改回；任务分组（`groupTasks`）在选中任务包含 `manual` 时智能继承；`Store` 新增 `resetTaskUrgencyMode(taskId)`。
- **详情面板交互与设置页说明（widgets/task_detail_panel.dart & screens/settings_screen.dart & l10n.dart）**：
  - 任务详情面板：当处于 `manual` 模式时展示“已手动调整紧急性”提示，并提供“恢复按截止日期自动调整”轻量按钮；点击后立即重置为 `auto` 并即时依据截止日期将紧迫任务自动升至 Q1/Q3。
  - 设置页与中英日三语词条：在“提前 N 天标记为紧急”滑块下方补充说明文案，动态显示 `{n}` 天说明；补充 `urgencyThresholdDesc`、`urgencyManualNotice`、`resetUrgencyAuto` 的 en/zh/ja 三语字典。
- **测试与回归（test/deadline_policy_test.dart & test/models_test.dart）**：
  - 新增 `deadline_policy_test.dart`（22 项测试），全面覆盖跨月/跨年/闰年/夏令时日历天计算、N 与 N+1 临界判定、自动升级与人工覆盖互斥、拖拽变 manual、详情面板恢复自动及设置页 UI 响应；
  - 验证：`flutter test --no-pub` **219/219**（全量通过，新增 22 项测试），`analyze --no-pub` **0 issues**。未做 Android/Windows 实机，未改 React。

## 2026-09-14 · WP11-N Flutter 数据版本迁移与导入格式演进契约

- **规范数据版本与迁移契约（docs/DATA_COMPATIBILITY.md）**：新增架构契约规范文档；明确区分持久化本地 Schema（核心 4 键不可变）与备份载荷版本（ExportData v1 vs v2）；梳理双向兼容矩阵与版本演进规则；明确旧版 React Web / 旧 Native 不支持未定义字段的客观事实，提供 v1 降级导出策略；确立未来新字段（如人工紧急性、备注、完成时间、提醒、标签）的标准演进流程。
- **小型迁移与校验引擎（data_migrations.dart）**：新增 `DataMigrator`，实现函数式安全解析与迁移门禁；前置校验 `version`（支持 v1/v2，未知高版本严格抛出 `UnsupportedDataVersionException`）；整份校验 boards 与 tasks 数据结构；自动清洗去重重复 ID，安全归宿/剔除孤儿任务；设置解析执行白名单过滤；全流程无副作用，确保原子事务性。
- **模型与存储层演进（models.dart & storage.dart）**：`ExportData` 升级当前标准版本为 `version: 2`，保留向前兼容解析能力与 `ExportData.version = 2` 既有符号兼容；`AppSettings.toJson({int? targetVersion})` 支持根据目标版本输出完整配置或剔除 v2 独有字段；`Store.exportJson({version})` 默认输出 v2，支持 `version: 1` 降级导出；`Store.importData` 全面接入 `DataMigrator`，前置验证失败原子中断，不篡改任何本地数据与看板代次（`boardEpoch`）。
- **合成测试与跨端往返验证（test/data_migration_test.dart & test/fixtures/）**：新增无密钥合成数据样例 `export-v1-minimal.json` 与 `export-v2-minimal.json`；新增 14 项完整迁移单元测试，覆盖 v1 自动升级安全默认值、未知高版本拒收、重复 ID 清洗、孤儿任务防御、损坏载荷原子回滚、迁移幂等性、Android 与 Windows 双端无损往返一致性；回归 `storage_test.dart`、`models_test.dart`、`bug_regression_test.dart` 全套 197 项自动化用例通过。
- **验证**：`D:\Dev_SDKs\Flutter_SDK\bin\flutter.bat test --no-pub` **197/197**（全量通过，新增 15 项测试），`analyze --no-pub` **0 issues**。未做 Android/Windows 实机，未改 React。

## 2026-09-12 · V0.3-A (WP26-A-N, WP26-B-N-Windows, WP27-A-N) 命令面板、快捷键、桌面托盘与统计进度

- **应用内命令面板与快捷键体系（WP26-A-N: shortcuts.dart & widgets/command_palette.dart）**：
  - 全局快捷键与意图体系：`matrixShortcuts` 映射 Ctrl+K 呼起命令面板、Esc 关闭/返回、Ctrl+N 新建任务、Ctrl+F 本地搜索、Ctrl+Shift+C 查看已完成、Ctrl+M 切换视图模式、Ctrl+, 设置面板、Ctrl+/ 快捷键帮助对话框。
  - 原生输入法与文本框焦点保护：在文本输入框获得焦点时（`_isTextEditingFocused()` 判定 `primaryFocus` 为 `EditableText`），快捷键自动让位，不拦截单键及原生文本操作（撤销/复制/剪切/粘贴），确保中文 IME 组词与正文编辑不受任何干扰。
  - 命令面板模态框（`CommandPaletteDialog`）：支持关键字即时模糊搜索应用内置核心命令以及跨看板的待办任务（复用 `queryTasks`）；支持键盘上下箭头高亮导航、Enter 执行与鼠标/触摸点击；命令覆盖导航、视图模式切换、设置与帮助，所有快捷操作均在界面有对应按钮替代，不强迫记忆快捷键；跨看板任务直接跳转原看板并打开详情面板高亮显示。
- **Windows 桌面壳集成与托盘（WP26-B-N-Windows: services/desktop_shell_service.dart & screens/settings_screen.dart）**：
  - 跨平台桌面抽象服务 `DesktopShellService`：在非桌面平台（Android / Web）采用安全空实现（no-op），无任何崩溃或平台通道异常；在 Windows 桌面抽象托盘生命周期、系统托盘右键菜单（显示主窗口、快速新建、本地搜索、退出应用）。
  - 关闭到托盘选项：`AppSettings` 扩展 `closeToTray`（默认 `false`）与 `globalShortcut`（默认 `'Ctrl+Alt+M'`）；设置页新增“桌面与系统设置”（`desktopSettings`）小节，提供关闭到托盘 Switch 开关与首次启用退出说明 SnackBar；支持窗口关闭拦截与托盘隐藏；全局热键支持冲突安全处理，冲突时不阻断应用正常启动与运行。
- **当前进度与完成统计条（WP27-A-N: task_stats.dart & widgets/task_stats_bar.dart）**：
  - 纯计算模型 `computeTaskStats`：精准计算父任务总数、已完成数、未完成数、完成百分比（针对空任务列表安全兜底 0%，彻底杜绝 100% 虚假显示）；父任务与子任务计数严格独立，杜绝父子双重计量；逾期统计（`overdueTasks`）仅对已超期且未完成的任务生效，已完成任务不计入逾期；统计计算不受 `hideCompleted` 偏好影响。
  - 统计条组件 `TaskStatsBar`：在主界面四象限/列表顶部呈现紧凑统计条；展示完成度百分比（如 `完成率: 50%`）、未完成徽章、逾期徽章（如有）、子项进度（如 `子项: 1/2`）以及看板范围切换按钮（当前看板 vs 全部看板）；采用 `Wrap` 弹性流式布局，彻底避免超窄屏及大字号缩放下的 RenderFlex 溢出；在已完成任务页（`CompletedScreen`）同步集成完成率状态。
- **中英日多语言扩充（l10n.dart）**：补齐 `commandPalette`、`shortcutsHelp`、`desktopSettings`、`closeToTray`、`statsCompletionRate`、`statsOverdue`、`statsSubtasks`、`statsScopeCurrent`、`statsScopeAll` 等三语字典词条。
- **验证**：`D:\Dev_SDKs\Flutter_SDK\bin\flutter.bat test --no-pub` **182/182**（全套测试 100% 通过，新增 16 项涵盖命令面板与快捷键、桌面抽象服务、任务统计计算与 TaskStatsBar UI 组件测试）；`analyze --no-pub` **0 issues**。未做 Android/Windows 实机，未改 React。

## 2026-09-12 · WP24-N Flutter 滑动操作、撤销与轻量反馈

- **撤销架构与命令快照（task_commands.dart & storage.dart）**：新增 `TaskUndoSnapshot` 与 `TaskUndoType`（complete 完成、restore 恢复、delete 删除）快照模型；保存单任务深拷贝、子项状态、看板 ID、象限与原始数组索引位置；`Store` 新增 `deleteTaskWithUndo(id)` 与 `toggleCompleteWithUndo(task)`，在删除或切换完成时原子捕获快照并返回；新增 `canApplyUndo(snapshot)` 与 `applyUndo(snapshot)`，在撤销窗口内支持原位置、原顺序精确恢复父子任务及级联状态；撤销只针对当前命令操作的数据，不保留整板回滚副本。
- **严格撤销失效契约与代数隔离（storage.dart）**：`Store` 建立看板代数（`_boardEpoch`）；在整板清空（`clearBoard`）、单象限清空（`clearQuadrant`）、删除看板（`deleteBoard`）以及覆盖导入（`importData(mode: 'overwrite')`）时自增看板代数；若任务已被后续编辑修改、目标看板已被删除或看板代数发生改变，撤销立即判定失效并提示（`undoUnavailable`），严防幽灵任务复活或覆盖最新状态。
- **卡片滑动交互与轻触觉反馈（widgets/task_card.dart）**：`TaskCard` 在普通模式下包裹 `Dismissible`（右滑标记完成/恢复、左滑删除）；多选模式自动关闭滑动（`DismissDirection.none`）；右滑完成平滑回弹并弹出带「撤销」动作的 5 秒浮动 SnackBar；左滑删除立即移除任务并弹出 5 秒「撤销」SnackBar；操作触发轻触觉反馈（`HapticFeedback.lightImpact`，Windows 平静降级）；右键次级菜单提供对等的一键完成/恢复、移动象限与删除动作及 5 秒撤销；预先捕获 `ScaffoldMessengerState`，杜绝卡片移除后 context 卸载导致的查找异常。
- **中英日多语言扩充（l10n.dart）**：补齐 `undo`、`complete`、`taskCompleted`、`taskDeleted`、`actionUndone`、`undoUnavailable` 三语字典词条。
- **验证**：`D:\Dev_SDKs\Flutter_SDK\bin\flutter.bat test --no-pub` **166/166**（新增 8 项 task_commands 单元测试与 4 项 task_card 滑动/右键/多选禁用/撤销端到端 Widget 回归测试，全套 166 项测试 100% 通过）；`analyze --no-pub` 0 issues。未做 Android/Windows 实机，未改 React。

## 2026-09-12 · WP08-T-N Flutter 字号与字体偏好

- **显示偏好模型与持久化（models.dart & storage.dart）**：新增 `FontSizePref` 枚举（`small` 0.88x、`standard` 1.0x、`large` 1.15x）与 `FontFamilyPref` 枚举（`system` 默认系统字体、`sansSerif` 无衬线体、`serif` 衬线体、`monospace` 等宽字体）；`AppSettings` 扩展 `fontSize` 与 `fontFamily` 字段，`fromJson` 支持反序列化与缺省安全兜底，`toJson` 输出显示偏好配置；`Store` 增加 `setFontSize(size)`、`setFontFamily(family)` 与 `resetDisplayPreferences()`（一键恢复默认主题、字号、字体与视图模式），变更时自动持久化到本地存储并触发通知。
- **动态排版体系与 TextScaler 适配（theme.dart & main.dart）**：`theme.dart` 增加 `fontScaleFactor`、`fontFamilyFor` 与 `fontFamilyFallback` 跨平台字体映射；实现 `CombinedTextScaler` 自定义 `TextScaler`，遵循 Flutter 3.16+ 规范，继承自 `TextScaler`，通过乘积复合应用系统无障碍字体缩放（`systemScaler.scale(fontSize) * appFontScale`），实现非弃用的 `scale(double fontSize)` 与 `double get textScaleFactor => scale(1.0)`，既不破坏用户系统的辅助功能字体缩放，又精准响应应用内小/标准/大字号偏好；在 `MaterialApp.builder` 与 `ThemeData` 中注入字体家族与文字缩放。
- **设置页偏好控制与即时预览（screens/settings_screen.dart & l10n.dart）**：设置页新增“字体与显示”（`fontAndDisplay`）小节；提供字号（小、标准、大）ChoiceChip 单选与字体系列（系统默认、无衬线、衬线、等宽）ChoiceChip 单选；下方提供即时排版预览卡片（`font-preview-card`），内含标题、正文与代表性象限任务预览，支持所见即所得动态刷新；提供“恢复默认显示”（`reset-display-btn`）按钮，一键还原显示偏好；补充中英日三语多语言词条。
- **验证**：`D:\Dev_SDKs\Flutter_SDK\bin\flutter.bat test --no-pub` **154/154**（新增 3 项 FontSize/FontFamily 单元测试与 2 项 SettingsScreen 端到端 Widget 回归测试，全套 154 项测试 100% 通过）；`analyze --no-pub` 0 issues。未做 Android/Windows 实机，未改 React。

## 2026-09-12 · WP08-V-N Flutter 宫格/列表视图切换

- **显示偏好模型与持久化（models.dart & storage.dart）**：新增 `ViewMode` 枚举（`grid` 宫格四象限模式、`list` 纵向分节列表模式）；`AppSettings` 扩展 `viewMode` 字段（默认 `ViewMode.grid`），`fromJson` 支持反序列化与缺省兜底，`toJson` 输出显示偏好；`Store` 增加 `setViewMode(mode)` 与 `toggleViewMode()`，两视图模式纯粹作为显示偏好，底层使用完全相同的 `tasks`、`visibleTasks` 与 `tasksIn(q)`，不复制、不重排、不篡改原始数据与 `createdAt`；支持本地设置持久化。
- **纵向四象限列表视图组件（widgets/task_list_view.dart）**：新增 `TaskListView` 组件；按紧急/重要四象限纵向分节排列；每个象限小节均展示象限代表色圆点、完整维度名称、当前象限任务数量角标；支持空态友好文字提示；无缝复用 `TaskCard` 组件，保持完成勾选、逐行删除线、子任务展开与折叠、多选高亮与编辑操作完全一致；每个象限整体包裹 `DragTarget<Task>` 并提供悬停高亮边框反馈与轻触震动，在列表模式下完全支持跨象限长按拖拽置顶移动与移动提示 SnackBar；象限头部提供点击进入单象限聚焦视图。
- **主界面与操作栏无缝集成（screens/matrix_screen.dart）**：`activeCenter` 依据 `store.settings.viewMode` 智能切换展示十字无框四象限宫格（`_grid`）与纵向列表（`TaskListView`）；单象限聚焦时平滑进入聚焦视图，退出聚焦无缝保留原视图模式；头部操作栏新增视图模式切换按钮（`ValueKey('view-mode-toggle-btn')`），支持一键在宫格（`Icons.grid_view`）与列表（`Icons.view_agenda_outlined`）间切换并展示多语言 Tooltip；将头部操作栏包裹于紧凑 `IconButtonTheme` 并微调水平边距，彻底解决 320px 超窄屏及系统 1.5x 文字缩放下 6 个操作图标按钮导致的水平溢出问题。
- **中英日多语言扩充（l10n.dart）**：补齐 `viewMode`、`viewModeGrid`、`viewModeList`、`noTasksInQuadrant` 三语字典词条。
- **验证**：`D:\Dev_SDKs\Flutter_SDK\bin\flutter.bat test --no-pub` **149/149**（新增 3 项 ViewMode 单元测试与 2 项 TaskListView/ViewMode 切换端到端 Widget 回归测试，全套 149 项测试 100% 通过）；`analyze --no-pub` 0 issues。未做 Android/Windows 实机，未改 React。

## 2026-09-12 · WP07-N Flutter 已完成任务集中查看

- **存储层直接查询与恢复机制（storage.dart）**：`Store` 新增 `completedTasks({boardId})` 与 `completedTaskCount({boardId})`；直接从底层 `tasks` 查询 `completed == true` 记录，不受 `settings.hideCompleted` 偏好影响，不复制任务对象，不伪造历史完成时间；新增 `restoreTask(task)` 与 `restoreTaskById(id)`，调用既有父/子级联规则 `setParentCompleted(task, false)` 将父任务及所有子任务重置为未完成，防止 `settings.autoCompleteParent` 因“子项全满”立即将父任务重新标完；恢复后任务立即在原看板、原象限中重新可见并持久化。
- **已完成任务集中视图（screens/completed_screen.dart）**：新增 `CompletedScreen` 页面；顶部提供返回键、标题与已完成数量副标题；支持范围过滤 Chip（当前看板 vs 全部看板，默认当前看板）；空数据时呈现友好空态图文；任务列表展示任务标题（带逐行删除线）、来源看板名称（跨看板或全部看板模式下展示）、来源象限（Q1–Q4 完整维度名及彩色圆点）；支持展开查看各子任务标题与完成状态；提供恢复勾选框与恢复图标按钮，点击触发任务恢复并弹出 SnackBar 提示；支持单任务安全永久删除，带二次确认弹窗，严格按 ID 作用，跨看板查看时不误删其他看板数据。
- **主界面入口接线（screens/matrix_screen.dart）**：在主界面头部操作栏新增“已完成”（`ValueKey('completed-btn')`）图标按钮（`Icons.task_alt`），点击无缝跳转至 `CompletedScreen(initialBoardId: store.activeBoardId)`。
- **中英日多语言扩充（l10n.dart）**：补齐 `completedTasks`、`noCompletedTasks`、`restoreTask`、`taskRestored`、`completedCount`、`deleteCompletedTask`、`confirmDeleteCompletedTask` 三语字典词条。
- **验证**：`D:\Dev_SDKs\Flutter_SDK\bin\flutter.bat test --no-pub` **144/144**（新增 3 项 Store 单元测试与 2 项 CompletedScreen 端到端 Widget 回归测试，全套 144 项测试 100% 通过）；`analyze --no-pub` 0 issues。未做 Android/Windows 实机，未改 React。

## 2026-09-12 · WP01-N Flutter 服务商预设与动态模型发现

- **服务商预设架构（ai_presets.dart & docs/AI_PROVIDER_PRESETS.md）**：建立主流服务商预设模型与配置（DeepSeek、火山引擎方舟/豆包、阿里云百炼 DashScope/通义千问、自定义 Custom）；遵循“只预设 Base URL 与必要协议元数据，不硬编码静态模型清单”原则，记录在新增规范文档中；支持针对特定服务商的智能首选模型算法（`pickPreferredModel`）。
- **模型数据与平滑迁移（models.dart）**：`AIConfig` 抽离 `provider` 服务商标识与通信协议 `protocol`；`fromJson` 完美向下兼容旧配置（旧 DeepSeek 配置自动归入 `deepseek` 预设，自定义端点归入 `custom`，火山/百炼链接精准识别），`toJson` 同步输出 `providerId` 与 `protocol`；测试与覆盖导入完美向前向后兼容。
- **动态模型发现与缓存服务（ai_service.dart）**：`AIService.fetchModels` 实现跨服务商安全模型发现；支持标准 `/models`、Anthropic `/v1/models` 解析；自动提取去重去空 `data[].id` 或 `models[].id`；状态码 401/403 映射为 `aiUnauthorized`，其他 HTTP 错误安全映射，不泄露响应体；基于 `${provider}|${baseUrl}|${apiKey}` 内存缓存，避免重复网络开销，支持 `forceRefresh` 与 `clearModelCache`；绑定 `AICancellation` 支持快速取消。
- **差异化思考参数适配（ai_service.dart）**：DeepSeek 原生专属 `thinking: {"type": "enabled"|"disabled"}` 控制参数精准绑定 DeepSeek 与自建代理；火山引擎与阿里云百炼等严格 OpenAI 兼容端点绝不附加 `thinking` 参数，彻底避免百炼等平台上 400 Bad Request 异常。
- **Key-only 快速配置交互与安全隔离（settings_screen.dart & l10n.dart）**：设置页新增服务商下拉选择；用户输入 API Key 失焦或提交后自动触发模型发现，严禁逐字符请求；模型列表动态展示并提供手动手填/推理接入点兜底；切换服务商立即取消旧请求、清空输入框 API Key 绝不跨端点泄露密钥并清除过期模型；高级 URL/协议配置针对预设折叠收敛、针对自定义完全展开；补充中英日三语多语言词条。
- **验证**：`D:\Dev_SDKs\Flutter_SDK\bin\flutter.bat test --no-pub` **139/139**（新增 4 项 dynamic discovery 与 provider adaptation 单元测试，2 项 SettingsScreen 端到端 Widget 回归测试，全套 139 项测试 100% 通过）；`analyze --no-pub` 0 issues。未做 Android/Windows 实机，未改 React。

## 2026-09-11 · WP02-N Flutter 一键清空当前任务板四个象限

- **看板菜单清空入口（matrix_screen.dart）**：主界面看板下拉菜单新增“清空此任务板”（`clearBoard`）操作项；当当前看板任务总数为 0 时，菜单项自动置灰禁用（`enabled: false`）；支持快捷呼起二次确认对话框。
- **确认弹窗与目标捕获（matrix_screen.dart）**：二次确认对话框标题为“清空任务板”（`clearBoardTitle`），正文明确提示目标看板名称与将被清空的任务总数（含已完成与隐藏任务，`clearBoardConfirm`）；在呼起弹窗时捕获目标 `boardId`，防止确认期间看板漂移误清其他看板；取消操作完全无害保留所有任务；确认操作执行单次原子清空并弹出 SnackBar（`boardCleared`）反馈。
- **原子状态更新与持久化（storage.dart）**：`Store.clearBoard(boardId)` 实现单次原子状态更新；一键删除目标看板下四个象限的所有任务（包括主任务及子任务，无论已完成或隐藏）；严格保留看板实体本身、其他看板及其任务、应用设置（`matrixflow-settings`）与 AI 配置（`matrixflow-config`）；清空后自动持久化到本地存储并触发通知；操作具备幂等性（空看板再次清空返回 0，无副作用）。
- **界面瞬态重置与在途 AI 结果作废**：清空操作同时重置多选模式（`_selecting = false`、清空选中集）、关闭活动任务详情抽屉/侧边栏（`_activeDetailTaskId = null`）以及象限聚焦状态（`_focusedQuadrant = null`）；引入 `_boardEpoch` 代数追踪机制，清空时自增看板代数；在途异步 AI 分析提交（`InputSheet`）检查代数，若目标看板已被清空则安全丢弃解析任务、提示友好错误并保留输入草稿，严防幽灵任务复活。
- **中英日多语言支持（l10n.dart）**：补充 `clear`、`clearBoard`、`clearBoardTitle`、`clearBoardConfirm`、`boardCleared`、`emptyBoard` 三语完整字典条目。
- **验证**：`D:\Dev_SDKs\Flutter_SDK\bin\flutter.bat test --no-pub` **133/133**（新增 1 项 Store 单元测试与 4 项针对空看板置灰禁用、取消保留任务、确认删除四象限/完成/隐藏/重置选择/跨看板隔离/重启保留、在途 AI 快照代数隔离防止复活的端到端回归测试）；`analyze --no-pub` 0 issues。未做 Android/Windows 实机，未改 React。

## 2026-09-11 · WP06-N Flutter 首次启动自动选择设备语言

- **系统设备语言解析（models.dart）**：新增 `resolveDeviceLanguage(Iterable<Locale>? locales)` 函数；在首次启动且无保存语言配置时，从 Android / Windows 系统语言优先列表优先匹配 `zh`、`ja` 与 `en`；`zh-CN`、`zh-TW`、`zh-HK`、`zh-Hans`、`zh-Hant` 等各中文区域及变体均映射至现有中文（`Language.zh`）；未支持的系统语言或空列表回退至 `Language.en`。
- **持久化与已有选择保护（storage.dart）**：`Store` 构造函数与 `init({List<Locale>? deviceLocales})` 支持注入设备语言（默认查询系统 `WidgetsBinding.instance.platformDispatcher.locales`）；仅在 `matrixflow-settings` 不存在或未配置有效语言时采用设备语言；若用户此前已明确选择语言（包括在中文设备上显式选用英文 `en`），读取时严格遵循用户已选值，决不覆盖篡改；首次无配置启动时初始默认看板名称（`defaultBoardName`）按系统语言自然生成（如中文系统为“我的任务”、日文系统为“マイタスク”）。
- **原生入口与测试注入（main.dart & helpers.dart）**：`MatrixFlowApp` 支持外部注入 `deviceLocales`；测试工具 `makeStore` 与 `setup` 支持自定义系统语言列表，无需 mock 整个底层引擎即可进行确定性多语言测试。
- **验证**：`D:\Dev_SDKs\Flutter_SDK\bin\flutter.bat test --no-pub` **128/128**（新增 7 项 models 单元测试与 7 项针对新装 zh/ja/en/不支持语言、明确旧档 en 保护、手动改语言跨重启保持、覆盖导入语言保留以及 `MatrixFlowApp` 注入的端到端回归测试）；`analyze --no-pub` 0 issues。未做 Android/Windows 实机，未改 React。

## 2026-09-11 · WP05-N Flutter 手动换象限置顶与普通拖动

- **跨象限显式移动置顶（storage.dart）**：在 `Store.moveTask` 与 `Store.updateTask` 中统一实现显式跨象限置顶规则；当任务跨象限移动后，自动插入到目标象限最前面（`_insertAtFrontOfQuadrant`），目标象限其他任务保持相对顺序；同象限操作不重排；其他象限任务和其他看板任务保持相对顺序；不篡改或伪造 `createdAt` 时间戳；保持截止日期自动升级原有规则不变；数据重启与导入导出后次序一致。
- **详情面板跨象限置顶（TaskDetailPanel）**：在详情面板修改象限 ChoiceChip 保存时，通过构建克隆副本调用 `store.updateTask`，准确感知象限变更并触发目标象限置顶。
- **Windows 鼠标右键移动菜单（TaskCard）**：`TaskCard` 支持鼠标右键/次级点击（`onSecondaryTapDown`）弹出原生“移动到”（`moveTo`）上下文菜单，清晰列出其余 3 个象限及其主题颜色圆点；点击即可触发移动、轻触觉反馈与短暂 SnackBar 反馈提示。
- **拖放与手势体验优化（QuadrantPane）**：保留普通轻滑滚动与 `LongPressDraggable` 长按拖动；增强拖拽悬停视觉高亮（主题色背景强调与半透明边框）；拖拽开始与结束触发轻触觉反馈（`HapticFeedback`）；目标象限若处于滚动状态，接收任务后平滑滚回顶部，确保新置顶的任务立即可见。
- **中英日多语言支持（l10n.dart）**：补充 `moveTo`（Move to / 移动到 / 移動先）与 `taskMoved`（Moved to {quadrant} / 已移动至 {quadrant} / {quadrant} に移動しました）三语字典条目。
- **验证**：`D:\Dev_SDKs\Flutter_SDK\bin\flutter.bat test --no-pub` **114/114**（在基线 110 基础上新增 4 项涵盖跨象限置顶、相对顺序与 createdAt 保持、详情面板换象限置顶、右键移动菜单与拖放已滚动目标回滚顶部的回归测试）；`analyze --no-pub` 0 issues。未做 Android/Windows 实机，未改 React。

## 2026-09-11 · WP22-B-N Flutter 子任务截止日期与独立编辑

- **子项独立截止日期与编辑表单（TaskDetailPanel）**：将详情面板中的子任务简单单行输入升级为完整编辑对话框（`_editSubtask`）；支持直接修改子任务标题、选择今天（`subtask-deadline-today`）、明天（`subtask-deadline-tomorrow`）、自定义系统日期选择（`subtask-deadline-custom`）以及清除日期（`subtask-deadline-clear`）；子任务列表行同步展示标题、日历小图标与格式化截止日期。
- **日期完全独立与超期温和提醒**：子任务截止日期与父任务截止日期完全独立，父任务日期的修改或清除不连带变更子任务日期，反之亦然；子任务截止日期晚于父任务时，展示非阻塞温和提醒（`subtaskDeadlineAfterParent`：“子任务截止日期晚于主任务”），不截断或篡改用户输入。
- **矩阵卡片角标与草稿保护联动**：在四象限矩阵展开子任务时，带有截止日期的子任务直观渲染 `_DeadlineChip` 胶囊角标展示剩余日历天数及今天/明天状态；详情面板草稿脏检测（`_isDirty`）完整对比子任务 JSON（包含日期变更），未保存退出时弹窗确认，防止误触丢弃修改。
- **验证**：`D:\Dev_SDKs\Flutter_SDK\bin\flutter.bat test --no-pub` **110/110**（新增 3 项针对子任务日期设置/清除/草稿跟踪、父子日期独立性与超期提醒、矩阵卡片子项日期徽章的回归测试）；`analyze --no-pub` 0 issues。未做 Android/Windows 实机，未调用真实模型，未改 React。

## 2026-09-11 · WP22-A-N Flutter 新建任务截止日期入口与快照隔离

- **新建任务截止日期选择器（InputSheet）**：普通添加与 AI 脑暴输入界面均提供直观的可选截止日期选择入口；支持今天（`deadline-today`）、明天（`deadline-tomorrow`）、自定义日历选择（`deadline-custom`，呼起系统 DatePicker）以及一键清除日期（`deadline-clear`）；未选择日期时不补造虚假截止日期，选择日期后以当天本地结束时刻（23:59:59）精准落库。
- **公共日期范围说明与子任务不继承**：选定截止日期时界面明确提示范围说明（`deadlineBatchScope`：“应用于主任务，子任务不默认继承”）；多行手动录入或 AI 分组生成时，公共日期完整赋予本次生成的主任务，而生成的子任务严格保持 `subtask.deadline == null`。
- **AI 提交时快照隔离与草稿保留**：AI 分类提交时原子捕获截止日期快照（`deadlineSnapshot`）、看板 ID 及输入文本；异步请求在途期间界面的后续改动不污染正在生成的任务结果；AI 执行失败或取消时完整保留用户输入草稿及选定的截止日期，任务落库成功后自动清空草稿与日期状态。
- **验证**：`D:\Dev_SDKs\Flutter_SDK\bin\flutter.bat test --no-pub` **107/107**（新增 3 项针对新建快捷日期、子任务不继承、AI 失败保留草稿的回归测试）；`analyze --no-pub` 0 issues。未做 Android/Windows 实机，未调用真实模型，未改 React。

## 2026-09-11 · WP12-S-N Flutter 本地搜索与多维筛选先行

- **本地查询模块（task_query.dart）**：新增纯 Dart 任务搜索与过滤模块，提供中英日大小写不敏感关键词匹配；支持父任务标题与子任务标题深度搜索；支持本地日历边界日期计算（今天、本周周一到下周一、本月1号到下月1号、逾期未完成、无日期）；1,000 条合成任务检索响应低于 50ms；按 ID 去重，不依赖后端，不预造 tags/notes 字段。
- **搜索与筛选界面（SearchScreen）**：新增 `screens/search_screen.dart`，AppBar 增加搜索入口按钮（`search-btn`）；提供当前看板与全部看板（`TaskScopeFilter`）切换、四象限单选/全选、完成状态（全部/未完成/已完成）以及日期范围过滤芯片；搜索命中子任务时清晰展示 `看板名 / 父任务标题` 面包屑路径与象限指示；支持就地切换完成状态并实时刷新；针对跨看板任务提供“前往任务板”（`goToBoard`）显式切换动作，常规退出安全保留主界面看板、视图与滚动状态。
- **详情面板定位高亮联动**：`TaskDetailPanel` 与 `showTaskDetailSheet` 增加 `highlightSubtaskId`，从搜索结果点击命中子项直达父任务详情并自动展开高亮对应子项；宽屏桌面支持同屏右侧详情侧边栏。
- **验证**：`D:\Dev_SDKs\Flutter_SDK\bin\flutter.bat test --no-pub` **104/104**（新增 10 项 task_query 单元测试与 4 项 search_screen 回归测试）；`analyze --no-pub` 0 issues。未做 Android/Windows 实机，未调用真实模型，未改 React。

## 2026-09-11 · WP23-N Flutter 单象限聚焦与下方收起卡片

- **单象限聚焦视图（QuadrantFocusView）**：新增 `quadrant_focus_view.dart`，用户点击四象限标题（或全屏图标）进入单象限聚焦模式；主工作区全宽呈现选中象限任务列表，支持完整的任务完成、展开、多选与编辑交互。
- **下方三象限收起卡片与直接切换**：未聚焦的其余三个象限按原始数字顺序在下方以精简卡片同屏展示，显示完整维度名称、对应象限主题色指示点以及任务计数（即使空象限也保留展示为 0）；点击任意收起卡片立即平滑切换主聚焦象限；下方卡片支持作为拖拽目标（DragTarget），拖动任务到下方卡片直接移动象限。
- **返回恢复矩阵与缓存保护**：主 AppBar 呈现直观返回按钮（`focus-back-btn`），点击或按系统返回键（PopScope）、或点击聚焦象限头部均可退出聚焦并恢复四象限十字矩阵及原始滚动位置；切换看板时自动重置聚焦状态并清理会话滚动缓存；卡片置于矩阵区域内部底部，不与底部安全区新增按钮（FAB）重合或遮挡。
- **验证**：`D:\Dev_SDKs\Flutter_SDK\bin\flutter.bat test --no-pub` **90/90**（涵盖进入聚焦视图、三张收起卡片按序排列、卡片点击切换聚焦、返回按钮与头部点击双重恢复矩阵、聚焦内任务勾选/编辑/隐藏联动、看板切换自动重置退出等）；`analyze --no-pub` 0 issues。未做 Android/Windows 实机，未调用真实模型，未改 React。

## 2026-09-11 · WP04-N Flutter 任务详情编辑、多行输入与弹层一致性

- **统一任务详情编辑面板（TaskDetailPanel）**：将分散的编辑逻辑集中为统一的 `TaskDetailPanel`。标题支持 1–5 行自适应多行输入，回车换行，Ctrl+Enter / ⌘+Enter 快捷键保存；提供完整四象限完整名称 ChoiceChip 单选、截止日期选择与清除、长期任务切换、直接触发 AI 智能拆解抽屉。
- **子任务就地完整管理与联动**：详情面板内直观展示子任务进度（已完成/总数），支持单行添加新子任务、就地点击重命名、快捷删除以及复选框切换完成状态；保存时与 Store 的 `autoCompleteParent` 设置双向自动级联。
- **自适应响应式布局**：宽屏桌面（宽度 ≥ 900dp）以 340dp 侧边栏（Right Sidebar）同屏展示，完全不遮挡四象限十字矩阵；窄屏移动端（宽度 < 900dp）以可拖拽底部半屏抽屉（Modal Bottom Sheet）呈现，界面在窗口动态缩放跨越 900dp 阈值时自动平滑转换。
- **草稿保护与弹层一致性**：点击遮罩/关闭按钮时对比初始草稿，无改动直接静默退出；存在未保存修改时弹出二次确认对话框（`discardChangesTitle` / `discardChangesConfirm`），防止意外丢失；面板内空白处点击仅收起软键盘不退出面板；顶部常驻保存按钮防止软键盘遮挡；删除任务带二次确认并防止已删除任务被保存复活。
- **验证**：`D:\Dev_SDKs\Flutter_SDK\bin\flutter.bat test --no-pub` **86/86**（涵盖多行输入/超长折行/快捷键保存、子任务 CRUD 与父级级联、草稿未修改静默关闭与修改确认丢弃、宽屏侧边栏同屏与窄屏抽屉转换、删除任务防复活、MF23 空行手动录入测试）；`analyze --no-pub` 0 issues。未做 Android/Windows 实机，未调用真实模型，未改 React。

## 2026-09-11 · WP03-N Flutter 十字无框矩阵与紧凑任务行

- **十字无框矩阵**：去除象限圆角外框（`QuadrantPane`），仅保留悬停/拖放局部浅色高亮；矩阵中央由 1px 细线构成横竖十字分割线，四象限独立滚动；任务行彻底去除 `Card` 白底、圆角与阴影，采用无框轻量容器；去除子任务左侧竖线。
- **紧凑任务行与首行对齐**：完成方框（约 20–22 dp，热区 48×48 dp）与正文标题首行精确对齐；正文 16sp/1.4 行高，字重 500，矩阵内最多显示 3 行；普通态点击正文打开现有任务编辑面板（`showTaskEditSheet`），复选框仅切换完成，箭头仅展开/收起，互不冒泡；任务行移除常驻编辑/删除/添加子项操作行，子项展开后保留子项复选框与标题。
- **安全区工具栏与多选编辑**：新增待办按钮（`FloatingActionButton.extended`）与批量工具栏移至矩阵外底部安全区，杜绝遮盖 Q4 底部任务；多选模式下仅选 1 项时工具栏提供「编辑任务」按钮，选 2 项及以上提供「编组」按钮，支持取消退出多选。为 WP23 保留象限标题点击回调（`onQuadrantTap`），未添加未接线的虚假按钮。
- **验证**：`D:\Dev_SDKs\Flutter_SDK\bin\flutter.bat test --no-pub` **80/80**（涵盖十字分割线、无白底卡片、多选单选编辑按钮、复选框点击不冒泡编辑、子项去竖线及 320px 1.5x 缩放）；`analyze --no-pub` 0 issues。未做 Android/Windows 实机，未改 React。

## 2026-09-09 · WP21-N Flutter 四象限完整维度名与 AI 分类描述

- **界面名称**：矩阵标题与编辑象限选项统一为 Q1 紧急且重要 / Q2 不紧急但重要 / Q3 紧急但不重要 / Q4 不紧急也不重要；英文、日文表达同一对维度。不再用马上做/计划做/授权做/不要做。窄屏标题最多两行，不省略“不”。内部 `qDo` 等枚举与 wire=1/2/3/4、象限位置未改。
- **分类提示词**：去掉 `(Do First)/(Schedule)/(Delegate)/(Don't Do/Delete)`；保留紧急/重要定义、JSON/wire 契约、三协议、思考、分组/拆解与无说教。生活/娱乐任务不先验为不值得做，Q4 不是删除指令。
- **验证**：`D:\Dev_SDKs\Flutter_SDK\bin\flutter.bat test --no-pub` **77/77**；`analyze --no-pub` 0 issues。未做 Android/Windows 实机，未调用真实模型，未改 React。

## 2026-09-09 · WP20-N Flutter 完成/多选分离、独立子项展开、逐行删除线

- **完成方框只表示 completed**：原生 `TaskCard` 不再用 `selecting ? selected : completed`。多选改为行高亮、「已选」标记和「多选任务 · 已选 N 项」；切多选/退出只改会话选择，不改完成数据。父子完成级联沿用 `setParentCompleted`。
- **子项独立展开**：删除「非 selecting 才渲染子项」门禁；显示「子任务 已完成数/总数」入口，按 `boardId/taskId` 保存本会话展开状态，默认收起，切模式/切板/重排按 ID 保留；新增子项自动展开该父任务。
- **逐行删除线**：`StrikeThrough` 改为文字自身 `TextDecoration.lineThrough`，不再在文本块垂直中线叠一条横条。
- **验证**：`D:\Dev_SDKs\Flutter_SDK\bin\flutter.bat test --no-pub` **74/74**；`analyze --no-pub` 0 issues。未做 Android/Windows 实机，未改 Web（WP20-W）。

## 2026-09-08 · 待办说教评语移除、设置可见性与文案精简、设置自动化与 4 组模型思考模式真机实测闭环

- **AI 提示词与卡片视觉纯净化**：
  - 彻底剥离任务卡片（Web 端 `TaskCard.tsx` 与原生端 `task_card.dart`）上的 `reasoning` 理由展示，杜绝冒犯用户的说教、道德批评或评价性言论。
  - 调整 Web 与原生端的 AI 系统提示词（`services/aiService.ts` 与 `matrixflow-native/lib/ai_service.dart`）：明确严禁输出观点、建议、说教或建议删除任务的言论，AI 输出模型纯粹归纳任务标题与必要子任务，任务卡片恢复极简清爽。
- **设置界面占位符与文案打磨**：
  - 原生端与 Web 端 Base URL、API 密钥与模型名称输入框均配置常驻浮动标签（`FloatingLabelBehavior.always`）与默认占位符，彻底解决默认占位不显示的问题。
  - 精简思考模式副标题说明文案，移除冗余的括号举例。
- **设置自动化 4 项核心功能实机（Redmi K70）全量实测**：
  - ① **AI 自动拆解隐藏拆解提示**（`suppressLongTermPrompt`）：关闭时弹出确认底部抽屉，开启后静默直接入象限，实测通过。
  - ② **AI 自动分组隐藏分组提示**（`suppressGroupPrompt`）：批量输入购物项等同类任务时，直接合并生成分类父任务与子项，无需二次弹窗确认，实测通过。
  - ③ **父任务自动完成**（`autoCompleteParent`）：子任务全部勾选时父任务自动勾选打叉；反选任意子任务时父任务自动恢复未完成状态，双向联动实测通过。
  - ④ **导出与导入待办**（`exportData` / `importData`）：完美适配 Android 16 SAF 系统文件选择器，生成标准 `matrixflow_backup_...json` 备份并支持完整还原。
- **4 组模型与思考模式组合实机（Redmi K70）对比实测**：
  - 测试用例覆盖长期/短期/重要/不重要/紧急/不紧急等多维复杂任务集合。
  - 组合 1：`deepseek-v4-pro` + 开启思考（耗时 ~12s，分类命中率 100%，卡片干净无说教）。
  - 组合 2：`deepseek-v4-pro` + 关闭思考（耗时 ~6s，分类命中率 100%，卡片干净无说教）。
  - 组合 3：`deepseek-v4-flash` + 开启思考（耗时 ~8s，分类命中率 100%，卡片干净无说教）。
  - 组合 4：`deepseek-v4-flash` + 关闭思考（耗时 ~3s，分类命中率 100%，响应最快且分类极准）。
- **自动化验证**：66 项 Flutter 单元/组件测试全部通过，`flutter analyze` 0 issues，Web Vite 构建成功（290.6 kB），TypeScript 0 错误。

## 2026-09-07 · Web 与 Native 双端新增 AI 思考模式控制、DeepSeek 默认配置与 Android 真机全流程验证闭环

- **AI 思考模式支持**：
  - Web 与 Flutter 原生端均增加「思考模式」开关（`enableThinking`），默认关闭，支持持久化。
  - 三协议完整适配：OpenAI 兼容协议支持 `thinking: {type: 'enabled'/'disabled'}`；OpenAI Responses 协议支持 `reasoning: {effort: 'high'/'none'}`；Anthropic Messages 协议支持 `thinking: {type: 'disabled'}` 或 `output_config: {effort: 'high'}`。
- **默认 AI 厂商与模型优化**：
  - 默认 Base URL 切换为 `https://api.deepseek.com`，默认占位与模型切换为 `deepseek-v4-flash`。
  - Web 与 Native 双端设置界面均加入高亮建议提示卡片：「建议：推荐使用 deepseek-v4-flash 并关闭思考模式，响应最快且分类准确率最高。」，三语同步适配。
- **Android 实机端到端全量验证（Redmi K70 - Android 16 / HyperOS）**：
  - 通过 ADB 在真实手机上安装 `app-release.apk` 并执行自动化 UI 与功能复测。
  - 涵盖 T01~T10 全部 10 项核心测试：安装与冷启动、设置默认配置、思考开关与提示卡片、三语切换与界面排版、DeepSeek 真实 API 连通性测试（绿色 SnackBar 提示）、手动任务与子任务录入流转、任务勾选完成/划线/隐藏/删除二次确认、8 个真实任务 AI 批量四象限分类（命中率 100%）、长期任务识别与多步子任务拆解、多看板创建与隔离切换。
  - 66 项 Flutter 单元/组件测试通过，静态分析 0 警告，Web 构建 290.7 kB 通过。

## 2026-09-07 · 解决 Android Release 构建 integration_test 插件注册编译阻塞 (B01)

- **定位根因**：Flutter CLI (`flutter_command.dart`) 在执行 `flutter build apk --release --no-pub` 时因 `--no-pub` 抑制了 `regeneratePlatformSpecificTooling`，残留 debug 阶段由 `pub get` / `test` 生成的 `GeneratedPluginRegistrant.java`（包含 `IntegrationTestPlugin`），而 Gradle 的 `flutter.groovy` 在 release 构建中剥离了 `dev_dependencies`，导致 Java 编译找不到类。
- **最小安全修复**：在 `matrixflow-native/android/app/build.gradle.kts` 配置 Gradle 预构建任务 `cleanDevPluginsFromReleaseRegistrant`，在 release 编译前自动清理 `GeneratedPluginRegistrant.java` 中的测试插件注册，不手改生成文件、不把测试依赖移入生产依赖、不修改全局 SDK。
- **发布验证**：Android release APK 成功构建（`app-release.apk` 22.8MB，`--release` 与 `--release --no-pub` 均通过）；Android debug 构建通过；64 项测试通过，`flutter analyze` 0 issues。正式关闭 B01。

## 2026-09-07 · 原生端深度 Bug 审查与集中修复

- 归纳并处理 29 类问题：启动容错、导入原子校验/去重、编组保留子任务、父子完成状态、活动板恢复、唯一 id、截止日期更新、Android 文件导出和 release 网络权限。
- 修复键盘双重 inset、窄屏溢出、拖拽与滚动冲突、未接通的批量选择、弹层返回误退出、控制器释放、桌面连续 AI 提交、跨板异步写入；补充三语 Material 本地化。
- AI 请求增加可取消传输与总超时，区分编组和拆解，拒绝不完整结果并保留输入；规范 Anthropic 地址和 JSON 对象提示词。
- 自动化测试由 20 增至 64，全部通过；`flutter analyze` 0 issues。Android debug、Windows release 构建通过。
- Android release 仍因 integration_test 插件注册不一致编译失败；实机端到端待执行。详见 [深度审查报告](NATIVE_BUG_REVIEW_2026-09-07.md)。
- Session 收尾：同步报告与交接并提交本轮成果；下一轮限定为定位并尝试解决 B01，保留已通过的回归验证和 Windows 构建结果。

## 2026-09-07 · 原生跨平台版集成与文档体系全量对齐

### 新增

- **MatrixFlow Native（Flutter 原生跨平台版）正式集成至主仓库**：
  - 采用 Flutter 3 + Dart 开发，Impeller / Skia 自绘引擎，无需 WebView，提供丝滑的原生系统交互与动效
  - 同一套 Dart 代码直接编译为 **Android APK** 与 **Windows 原生桌面应用**
  - **数据完全互通**：同构数据模型（`models.dart`），与 Web 端共享 `ExportData` v1 格式与 SharedPreferences 本地持久化（键名对齐 `matrixflow-*`），支持去重合并
  - **三协议 AI 客户端**：原生 HTTP 实现 OpenAI Compatible、OpenAI Responses 与 Anthropic Messages 三协议，多级 JSON 容错剥离与探活检测
  - **工程化质量保障**：配备 20 项完备的单元与集成测试（`flutter test`），并通过 `flutter analyze` 零告警静态检查

### 改进

- **文档体系全面核验与对齐**：
  - 修复 `matrixflow-native/README.md` 指向 Web 版的失效相对路径
  - 更新 `README.md`、`AGENTS.md`、`docs/ARCHITECTURE.md` 与 `docs/DEVELOPMENT.md`，完整记录双轨（Web / Native）架构
  - 纠正 `ARCHITECTURE.md` 中历史残留的「AI 四协议」说法为三协议，更新 App.tsx 实际行数（1672 行）
  - 从技术债清单移除已消除的 Rollup 500 KB 分包警告，记录当前 Web 构建产物实际体积为 288.5 KB（gzip 87 KB）
  - `DEVELOPMENT.md` 补齐 Flutter 开发、构建、测试命令与本机 SDK 路径说明，修正 subst 映射路径

## 2026-09-06（二）· 移除 Gemini 协议

### 移除

- **按用户决定移除 Gemini 调用协议**：删除 `@google/genai` 依赖与构建期密钥注入（`vite.config.ts` 的 `define`），AI 配置只剩三种自定义协议，项目不再依赖任何环境变量或 `.env` 文件
- 旧配置中 `provider: 'gemini'` 或 `'custom'` 在加载时自动迁移为 OpenAI 兼容协议，默认提供商改为 OpenAI 兼容

### 改进

- 构建产物从约 507 KB 降至 **288 KB**（gzip 121 KB → 87 KB），Rollup 分包警告随之消失
- tsconfig 补充 exclude（src-tauri / android / dist），避免类型检查扫到打包壳的生成文件

## 2026-09-06 · AI 多协议与跨端打包

### 新增

- **AI 多协议调用**：除 Gemini 外，新增三种自定义调用方式，统一「API 地址 + 模型名 + 密钥」三要素配置：
  - **OpenAI Compatible**（`{baseUrl}/chat/completions`，适用 DeepSeek、Moonshot、SiliconFlow 等兼容服务商）
  - **OpenAI Responses**（`{baseUrl}/responses` 新版接口）
  - **Anthropic Messages**（`{baseUrl}/v1/messages`，`x-api-key` + `anthropic-version` 头）
  - 旧「Custom API」配置自动迁移为 OpenAI Compatible，无需手动处理
- **按协议探测的测试连接**：OpenAI 系走 `GET /models`，Anthropic 走 `GET /v1/models`（代理不支持时自动降级为 1-token 最小请求探活）
- **桌面应用（Windows）**：采用 Tauri v2 打包（WebView2 内核，产物含 NSIS 安装器与便携版），源码在 `src-tauri/`，构建命令 `npm run tauri build`
- **安卓应用**：采用 Capacitor 封装（WebView 加载同一份 `dist/`），源码在 `android/`，构建命令见 README；debug APK 可直接安装

### 改进

- JSON 解析兜底增强：自动剥离 markdown 代码围栏、兼容单对象响应；象限字段兼容 "Q1" 字符串（DeepSeek 实测返回字符串而非整数）
- 协议参考实现来自开源项目（NextChat 的 anthropic/deepseek 适配器等），地址规范化：无协议前缀自动补 https、去除尾部斜杠

## 2026-09-03 · 交互与健壮性专项修复

依据全面审核报告（26 项发现，双重冷复核 + 浏览器实测）完成的集中修复。

### 修复（高优先级）

- **合并导入不再产生重复任务**：导入去重按任务 id 过滤，并丢弃指向不存在任务板的孤儿任务（此前同一备份导入两次会产生连 id 都相同的重复任务，引发 React key 冲突）
- **移动端可以更改任务象限**：编辑模态新增象限选择器（此前移动端既无法拖拽、编辑里也无象限字段，完全没有改分类的途径）
- **AI 请求 30 秒超时**：Gemini 与自定义 API 全部请求经 AbortController 中止，错误提示「请求超时」；单任务拆解弹窗改为可关闭，不再可能被挂起请求锁死界面
- **本地数据损坏不再白屏**：localStorage 读取改为安全解析（损坏时重置该项并提示），新增 ErrorBoundary 兜底（附「清除本地数据并重载」逃生入口）
- **删除全部任务后刷新不再复活旧数据**：持久化改为 hydration 完成后生效，空列表也会写回

### 修复（交互）

- 弹窗支持 **Esc / 点击遮罩关闭**，补齐 `role="dialog"`、`aria-modal`、关闭按钮 aria-label 与焦点圈（focus trap）
- 提交快捷键兼容 **Ctrl（Windows / Linux）与 ⌘（macOS）**，并在输入区显示提示（此前只识别 ⌘，Windows 下快捷键完全无效）
- **7 处原生 alert 全部替换为 Toast 通知**（自动消失、可手动关闭、成功/错误两种样式）
- 移动端任务标题不再被动作按钮挤成一字一行（标题保底 120px，操作按钮换行）
- 子任务的编辑/删除按钮改为常显（此前仅悬停可见，触屏不可达）
- 移动端多行文本手动添加按行拆分为多条任务（与 AI 模式行为一致，此前整段文本含换行符存为一条标题）
- 任务卡不再静默截断子任务（移除 max-h-96 限制）
- **AI 分类理由（reasoning）现在会显示**在任务标题下方（此前字段被完全丢弃）
- 覆盖导入前增加**二次确认弹窗**（复用现有确认系统）
- 新增「**隐藏已完成**」开关（设置项 `hideCompleted`，含导入白名单同步）

### 修复（打磨）

- 移除 viewport 禁止缩放（`user-scalable=no`），恢复用户缩放能力
- 滚动条不再全局隐藏：`custom-scrollbar` 类有了真实样式（6 处滚动区域恢复滚动指示），并移除该死类名的历史遗留
- 可访问性：设置齿轮、移动端 FAB、主题色圆钮、开关滑块、自定义 API 输入框补齐 aria 标注；`<html lang>` 随界面语言实时切换
- 清理 AI Studio 遗留：删除指向 aistudiocdn 的休眠 importmap 与不存在的 `/index.css` 引用（构建警告消除）
- 任务卡左侧增加象限颜色条、象限容器顶部增加彩色细条（此前四象限视觉上完全同色）；启用了 TaskCard 一直未使用的 `colors` 属性
- 截止日期按**本地时区**解析（此前按 UTC 午夜解析，东八区偏差 8 小时）
- 设置页新增 AI「**测试连接**」（自定义 API 走 `{baseUrl}/models` 探测；Gemini 校验注入密钥存在性）
- 拖拽移动任务增加目标象限高亮反馈
- Quadrant / TaskCard 组件 `React.memo` 化，App 处理函数 `useCallback` 化，输入打字不再全树重渲染
- 三语硬编码清理：导入预览 ON/OFF、天数单位 `d`、删除按钮文案键误用等；英文截止日期显示 `3days` → `3d`
- **补装缺失的 `@types/react` / `@types/react-dom`**：此前 `tsc --noEmit` 是在无 React 类型下通过的空验证，现在类型检查真实生效（计入 devDependencies）

### 验证

`npx tsc --noEmit`（真实类型）通过；`npm run build` 通过；浏览器实测通过：多行拆分、象限改分类、Esc/遮罩关窗、Toast 错误反馈与自动消失、隐藏已完成、删空刷新不复活、损坏数据自愈、中文切换联动 `html lang`、移动端标题布局（14px 竖排 → 126px 正常换行）。

## 2025-11-25 · 任务编辑体验打磨

`0e2d51f` **feat(任务编辑): 重构任务编辑功能并添加动画效果**

- 新增专用编辑按钮（铅笔图标）与滑动动画
- 编辑模态框支持批量操作与行内编辑（子任务 / 父任务标题）
- 输入区域支持动态高度调整
- 优化确认模态框动画与状态管理

## 2025-11-24 · 数据安全与代码结构

### 新增

`7a8e0e2` **feat(数据备份): 添加数据导入导出功能及相关UI组件**

- 数据导出为 JSON 备份文件（`ExportData` v1 格式，含任务板、任务、设置与 AI 配置）
- 数据导入：支持「合并」与「覆盖」两种模式，导入前可逐项勾选预览

`63519a2` **feat: 添加自动完成父任务功能及UI改进**

- 新增设置项：全部子任务完成时自动勾选父任务
- 删除操作增加确认模态框；模态框增加淡出 / 滑出动画
- 任务卡片复选框样式与完成动画改进；输入区底部添加版权信息

### 变更

`50c70cc` **refactor: 将组件拆分为独立文件并优化代码结构**

- 将约 1400 行的单文件 App.tsx 拆分为 `components/` 与 `components/ui/` 模块（Quadrant、TaskCard、InputArea、SettingsControls、ImportReview、Modal、Checkbox、ToggleSwitch），功能不变

## 2025-11-22 · 核心功能日

### 新增

`d986fdd` **feat: 初始化 MatrixFlow AI 项目，实现任务管理矩阵和AI智能分类功能**

- 艾森豪威尔四象限矩阵：任务卡片拖拽重分类
- AI 智能分类：自动判定象限并给出理由，支持单条与批量输入
- 多语言界面（英文 / 简体中文 / 日文）
- 主题切换（亮 / 暗 / 跟随系统）与 5 种主题配色
- 多任务板管理
- AI 服务双提供商：Gemini 与 OpenAI 兼容自定义 API
- 响应式设计与移动端适配

`52a7de2` **feat(任务管理): 添加子任务和分组功能**

- 子任务（SubTask）类型与任务卡展开管理
- AI 任务分组：多条同类输入合并为一个任务（如「买牛奶 + 买鸡蛋 → 购物」）
- AI 批量分解：对长期任务批量生成子任务

`7a93d1b` **feat: 新增AI自动拆解功能及相关设置选项**

- 新增设置项：AI 自动拆解（autoDecomposeAI）、抑制分组确认提示（suppressGroupPrompt）、抑制长期任务提示（suppressLongTermPrompt）
- 长期任务标记（FlagIcon）与状态切换
- 象限一键清空功能
- AI 服务支持「即时拆解」：分类阶段直接为长期任务生成子任务
