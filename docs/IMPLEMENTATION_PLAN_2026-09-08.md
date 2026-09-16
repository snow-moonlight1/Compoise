# MatrixFlow AI：体验修复与功能演进执行计划

初稿：2026-09-08；最新修订：2026-09-16。当前代码基线：`main` / `747eb35` + V0.2 + V0.3-A + V0.3-B（全量 255 项自动化通过）；项目根目录：`D:\Dev_project\martix`。

> **路线已确定：继续 MatrixFlow 独立开发，参考 Focus 的交互，不 fork、不搬代码、不跟进其 issue/PR。** 目标是开源本地客户端、发布 GitHub Release 并上架应用商店，保留 BYOK，后续提供可选 ¥9/月、有额度的托管 AI 服务。用户不安排几十人试用；采用助手自动化回归与必要的设备验收。**Flutter Android/Windows 为唯一持续开发客户端；React / Tauri / Capacitor 冻结保留。WP20-N、WP21-N、WP03-N、WP04-N、WP23-N、WP12-S-N、WP22-A-N、WP22-B-N、WP05-N、WP06-N、WP02-N、WP01-N、WP07-N、WP08-V-N、WP08-T-N、WP24-N、WP26-A-N、WP26-B-N-Windows、WP27-A-N、WP11-N、WP22-C-N、WP13-A-N、WP25-R、WP25-N-Android、WP25-N-Windows、WP27-B-N、WP09-N 已完成（自动化/研究与契约，V0.3-B 阶段全部闭环收官）；WP20-W 未开工，已取消。下一实施助手领取 WP10-N 或 V1.0 发行准备（WP28-R）。**

WP20-N、WP21-N 与 WP03-N 已实施：完成/多选/展开/逐行删除线、完整紧急/重要象限名称与分类提示词，以及十字无框矩阵与紧凑任务行。最新自动化为 `flutter test --no-pub` 80/80 与 `analyze --no-pub`。本文其余工作包仍按一次一包领取。后续 Agent 完成后报告，不自行展开整张路线图。

本版保留已有 42 项需求和 WP01–WP29 编号，将未实施工作包统一收敛到 Flutter；单象限聚焦、手势撤销、提醒、桌面效率、统计、发行与托管服务进入明确工作包。WP12 拆为先搜索、后标签，WP13 拆为先基础备注、后可视 Markdown。原 [交互复核](UI_INTERACTION_REVIEW_2026-09-08.md) 仍解释已有 Bug 根因；[方向研究](STRATEGY_REVIEW_2026-09-08.md) 的 fork 比较和多人试用建议已成为历史，不再作为执行任务。

## 1. 结论、基线与边界

- 保留此前 35 项需求；新增 MF37–MF43，现为 **42 项、29 个工作包**。工作包各有小型子批次，不代表需要 29 轮重构；父任务自动完成、换行批量添加、主题等已有能力只回归，不重复开发。需求数量不是 Bug 数量。
- **完成/选择语义与子任务入口已由 WP20-N 修正，下一步统一名称，再做无框矩阵、集中详情编辑和日期入口，随后接服务商/其他功能。** 用户已明确 custom API 目前没有故障，原条目已并入服务商预设；不新建 API 故障调查任务。当前无证据判定存在 P0 数据损坏事故。
- **平台契约已生效：** Android 与 Windows 共用 `matrixflow-native/` 的 Dart 模型、Store、AI 服务和主要 UI；Android 检查触摸/键盘，Windows 检查鼠标/键盘/焦点/窗口缩放。能编译不等于桌面交互验收完成。
- **N = Flutter 共享实现；旧 W = React Web，不是 Windows。** 未实施的 W 子批次全部取消，不标为完成。下文“双端/跨端”指 Flutter Android/Windows；第 6–7 节保留的旧 Web 证据仅供历史参考。
- **React 冻结边界：** 保留现有根目录源码、Tauri/Capacitor 壳及旧版导入导出，不移动/删除文件，不做功能对齐，不因 Flutter 改动运行 Web build/tsc。仅用户另行安排旧版严重问题时单独处理。Flutter Web 暂不纳入本轮；介绍/下载网站不等于第二套待办客户端。
- **数据演进：** 新 Flutter 继续读旧 Web/Native ExportData v1，Android/Windows 使用同一新格式。未来字段按 WP11 演进，不再修改冻结的 `types.ts` 来让旧 Web 理解新格式；兼容导入不等于自动跨设备同步。路线依据见 [已采纳 ADR](ADR_FLUTTER_PRIMARY_2026-09-09.md)。
- B01 已关闭；VS C++ 工具链已安装且 Windows release 曾构建通过。下一轮不再定位 B01，也不重新安装工具链。
- 已验收基线：卡片不展示说教/理由；默认 DeepSeek Base URL 与 `deepseek-v4-flash`；Pro/Flash × 思考开/关四组合；隐藏拆解/分组提示、父任务自动完成、导入导出。**保留这些行为与现有开关，不重做，不恢复理由展示。** 用户撰写的备注是新字段，不能复用历史 `reasoning`。
- WP20-N 的 Flutter 74/74、analyze 0 是当前自动化基线；此前 66/66 与 Web build/tsc 为更早历史结果，本次文档调整均未重跑。`docs/HANDOFF.md` 引用的 `real_device_test_plan.md` 在当前工作区（含忽略文件搜索）未找到；不把缺失的历史记录当成验收失败，也不编造日志。
- 任务和任务板继续本地保存；BYOK 直连用户选定服务商，不经过运营者服务器。WP29 的可选托管服务允许独立服务端保存账号、订阅和额度账本，不上传完整待办库，不把它当成 WP18 云同步。网盘同步仍为后期自愿功能；不登录、不付费、离线或服务器停机，都能使用本地待办。
- 发布目标明确后，签名、图标合规、隐私说明与商店材料纳入 WP28；仍不做无关 Web 状态重构和额外壳平台重写。公开仓库、创建收费产品、实际部署和提交商店在对应发布子批次完成准备后执行，不在本规划轮代办。

### 最终产品与版本路线（执行摘要）

| 阶段 | 用户得到什么 | 为什么这样排 |
|---|---|---|
| V0.2：先把每天用的流程做顺 | 完成/多选正确、子项可展开；十字矩阵、全宽单象限+下方三张收起卡、点任务编辑、搜索、日期和移动顺手 | 基础交互可信，已有 AI 和多 Board 才能发挥作用 |
| V0.3：补齐 Focus 中值得借鉴的日常能力 | 列表/字体、基础备注、滑动撤销、提醒、已完成与统计、Windows 快捷操作；保留全部 MatrixFlow 能力 | 独立实现成熟交互，不迁移底座、不退回单 Board |
| V1.0：开源与发行 | GitHub 源码/Release、Flutter Android/Windows；介绍/下载页按需；基础待办免费，BYOK 配置容易，应用商店逐个上架 | 给作品稳定入口；上架和开源无需等待复杂 Planner/网盘功能 |
| V1.1：可选省心 AI | 用户可直接订阅 ¥9/月服务，无需自己配置服务商；明确额度，BYOK 继续可用 | 服务端承担密钥、账号、支付和额度，付费购买便利；不强迫全体用户注册 |
| 后续版本 | 完整 Markdown、标签、Today/Planner、系统笔记导入、网盘同步、开发模式等原需求 | 保留全部需求，按依赖派单，不把每项都变成首次发布的门槛 |

“9 元包月”是价格方向，**不是无限 tokens**。建议首版以 100 点/月为额度草案，短请求约 1 点、复杂请求预先显示点数，最终计点/上限由 WP29-R 用合成样本与成本预算确定。订阅到期只停止托管 AI，本地任务、编辑、导出、BYOK 不受影响。不再设置用户访谈、20 人试用或付费人数门槛。

### 用户澄清与本轮设计决定

| 项目 | 当前解释 | 执行时需要补充什么 |
|---|---|---|
| AI 配置（用户已澄清） | 选择内置服务商，填写 Key，实时请求模型列表；不内置模型清单 | 首批 DeepSeek、火山引擎、阿里云百炼；逐家核验地址、鉴权与模型发现 API，不假定全部是 /models |
| 一键清除（用户已澄清） | 四象限主界面一次删除四个象限里的全部任务；**不是完成、不是归档** | 按当前 board 的四象限处理；跨所有 board 擦除不在本条范围 |
| 系统笔记待办导入（用户已澄清） | 从各厂商系统笔记的待办导入；第一目标小米包名 com.miui.notes | 仍需验证目标版本是否提供公开导出、分享或受支持的数据接口；包名不等于数据访问权限 |
| 文字与复选框不在同一行 | 理解为当前问题，目标是复选框与标题首行对齐 | 按 WP03 验收 |
| 编辑父项与子项 | 编辑现有父/子任务的内容和日期 | 不默认包含任意改父节点、无限嵌套；那会改变现有一层子任务模型 |
| 空白关闭模态框 | 指弹层外的遮罩区域 | 弹层内部留白不关闭；点击内部留白可收起键盘 |
| 完成归档 | 第一版提供“已完成”集中查看与恢复，直接查询已有 completed | 不新增自动删除规则，不预先引入另一套 archived 状态 |
| 拖到其他块 | 第一版是同一 board 内跨象限 | 跨 board 移动另行定义，避免把子任务与任务板关联弄乱 |
| 跟随手机语言 | 首次启动/语言缺省时选系统支持语言，保留用户明确选择 | 不强制随系统变化覆盖用户已选语言 |
| 普通/编辑模式（新截图） | 代码中的 selecting 实为多选；用户按控件是否可见理解成另一种模式 | 取消“全局编辑模式”命名，完成方框只代表完成，多选另用行高亮和数量 |
| 手机窄象限 | 十字无框背景 + 轻量任务行 + 可展开子项 | 手机全宽底部详情、宽屏右侧详情；不为每条任务附满编辑工具 |
| 四象限名称 | 按紧急/重要两个维度直接命名 | q1–q4 数值与位置不变；删除 UI 行动式短名及提示词括号建议 |
| Deadline | 新建可选、父子都可编辑、与计划日分开 | 规则/颜色/阈值统一；人工紧急性优先需要 WP22-C 的持久化字段 |
| 点象限放大 | 当前象限全宽；另外三个在下方缩为标题+数量卡片 | WP23 独立实现，不以普通纵向四列表代替 |
| Focus 参考边界 | 独立实现已核对的交互，继续多 Board、父子任务、AI、数据互通 | 不复制其代码/素材，不追踪其 issue/PR；已有主题等只完善反馈 |
| 免费与收费 | 本地功能免费；BYOK 自付模型费用；可选 ¥9/月托管 AI | 任务不迁云；托管账号/订阅/额度与本地备份分开 |

## 2. 完整需求清单与优先级

来源 A 为图一从上到下第 1–15 条；来源 B 使用图二原编号 11–24，末尾两条记 B25、B26。P1：核心操作/明显高频问题；P2：效率和可发现性；P3：低频或高成本扩展。工作量 S/M/L/XL 是相对范围，不是额度或耗时承诺。

| ID | 来源 | 去重后的需求 | 当前判断 | 优先级 / 量级 | 工作包 |
|---|---|---|---|---|---|
| MF01 | A1 + 新截图 | 手机模式入口语义明确 | 原“换铅笔”建议更新为显式“多选”；铅笔仅代表真实编辑 | P1 / S | WP20 / WP03 |
| MF02 | A2 | 手动换象限后置顶 | Flutter 当前只更新 quadrant，未调整顺序 | P1 / S | WP05 |
| MF03 | A3 | 从系统笔记待办导入 | 小米 com.miui.notes 优先，其他厂商逐家核验 | P2 / L | WP17 |
| MF04 | A4、B24 | 使用引导、首次教程 | 同一需求，合并；教程可再次打开 | P2 / M | WP09 |
| MF05 | A5 | 普通模式直接跨象限拖动 | Flutter 已有普通模式长按拖动及 Widget 用例；需体验核验 | P1 / S–M | WP05 |
| MF06 | A6 | 复选框与标题首行对齐 | Flutter 标题区域为 Column，代码可见不同行 | P1 / S | WP03 |
| MF07 | A7、A8 + 新截图 | 十字无框矩阵、任务轻量行、控件移出 | 覆盖原仅减弱边框方案；手机全宽详情、宽屏侧栏 | P1 / M | WP03 / WP04 |
| MF08 | A9 | 编辑框多行 | 父任务部分已有；子项/分组行内入口不一致 | P1 / M | WP04 |
| MF09 | A10 | 默认使用手机语言 | Flutter 缺省硬编码 en | P1 / S | WP06 |
| MF10 | A11、B25 | 服务商预设 + Key + 实时模型列表 | 用户澄清为功能，无当前 API 故障；MF28 并入本项 | P1 / M–L | WP01 |
| MF11 | A12 | 输入框随内容增高 | Flutter 新增框为 3–5 行；需统一输入与编辑边界 | P2 / S | WP04 |
| MF12 | A13 | 方便编辑父项、子项 | 已有编辑能力，入口与多行行为需补齐 | P1 / M | WP04 |
| MF13 | A14 | 点击遮罩关闭模态框 | Flutter 使用默认可关闭弹层；逐入口核验草稿规则 | P2 / S | WP04 |
| MF14 | A15 | 已完成任务归档入口 | 只有隐藏已完成开关，无集中入口 | P2 / M | WP07 |
| MF15 | B11 | 宫格/列表模式 | 新视图，复用同一数据 | P2 / M | WP08 |
| MF16 | B12 | 字体大小设置 | 新设置，必须考虑系统文字缩放 | P2 / M | WP08 |
| MF17 | B13 | Markdown 备注与所见即所得编辑 | 新数据字段与编辑器集成，先做选型验证 | P2 / L | WP13 |
| MF18 | B14 + Focus 对照 | 搜索先行，标签后续 | 先查已有标题/子项与组合过滤，标签再增字段 | 搜索 P1 / M；标签 P2 | WP12-S / WP12-T |
| MF19 | B15 | Planner/Schedule，跨 board 取任务 | 新业务模型与页面，先定义排期语义 | P2 / L | WP15 |
| MF20 | B16 | 今天待办页 | 新聚合视图，区分截止日与计划日 | P2 / M | WP14 |
| MF21 | B17 | 子任务全完成则父任务完成 | **已实现且用户确认验收通过**；保留开关及反选恢复 | 回归项 | WP04 / WP07 |
| MF22 | B18 | 今日待办全部完成庆祝 | 依赖稳定的“今天”集合 | P3 / S | WP16 |
| MF23 | B19 | 普通模式按换行批量添加 | **Flutter 已实现**；补使用提示即可 | 回归项 | WP04 / WP09 |
| MF24 | B20 | 多选任务一起拖动 | 现有选择用于编组，并禁用拖动 | P2 / M | WP10 |
| MF25 | B21 | 网盘授权同步、WebDAV、本地文件/P2P | 多个独立适配器及冲突合并系统 | P3 / XL | WP18 |
| MF26 | B22 | 更改字体 | 与字号共同形成显示偏好 | P2 / M | WP08 |
| MF27 | B23 | 开发管理模式，AI 分 feature/fix | 可选任务板模式，不能覆盖重要/紧急维度 | P3 / L | WP19 |
| MF29 | B26 | 一次清空主界面的四个象限 | 当前仅有逐象限清空；补齐整个当前 board 的清空动作 | P1 / S–M | WP02 |
| MF30 | 新截图/描述 | 完成方框、删除线、隐藏行为一致 | WP20-N 已修复，74 项自动化通过；设备新交互待验 | P1 / M | WP20 |
| MF31 | 新截图/描述 | 所有浏览状态可展开子任务 | WP20-N 已移除门禁并独立展开；保留为回归项 | P1 / M | WP20 |
| MF32 | 本轮补充 | 使用完整紧急/重要名称，清理 AI 行动建议 | 旧短名自初始化已存在，不归因于最近 Agent | P1 / S | WP21 |
| MF33 | 本轮补充 | 普通/AI/批量新建可设置截止日期 | Flutter 新增输入缺日期入口 | P1 / M | WP22-A |
| MF34 | 本轮补充 | Native 子项截止日期编辑与清除 | 模型已有字段，UI 只改标题 | P1 / M | WP22-B |
| MF35 | 本轮复核 | 阈值解释、日历天、提示颜色、人工调整一致 | 2 天硬编码与设置 N 天不同；手动移动可能被自动升级覆盖 | P1 / M | WP22-C |
| MF36 | 本轮静态发现 | 多行标题逐行删除线 | WP20-N 已改为逐行文字删除线；保留为回归项 | P1 / S | WP20 |
| MF37 | 用户指定 | 单象限放大、其他三个下方缩起 | 新浏览状态；与矩阵/列表共用任务数据 | P1 / M | WP23 |
| MF38 | Focus 对照 | 滑动完成/删除、撤销与清楚反馈 | 独立补手势，不能复活其他已删数据 | P2 / M | WP24 |
| MF39 | Focus 对照 | 主/子任务可选时间提醒 | 新本地通知能力，截止日与提醒时刻分开 | P2 / L | WP25 |
| MF40 | Focus 对照 | Windows 托盘、快捷创建、搜索/命令面板、全局唤起 | Flutter Windows 平台能力；共享命令提供触摸替代入口 | P2 / L | WP26 |
| MF41 | Focus 对照 | 当前完成进度、最近完成与按日统计 | 当前计数可先做，完成时间不能由 createdAt 推算 | P2 / M | WP27 |
| MF42 | 用户确认路线 | 独立开源、GitHub Release、应用商店发行 | 发行工程和材料，保持免费本地/BYOK 入口 | 发布必需 / L | WP28 |
| MF43 | 用户确认路线 | ¥9/月可选托管 AI | 账号/订阅/额度/模型代理的新服务端；不迁任务库 | 发行后 / L | WP29 |

## 3. 派单顺序与控制范围

**下一包可领取 WP10-N 或进入 V1.0 发行准备（WP28-R）。** WP20-N、WP21-N、WP03-N、WP04-N、WP23-N、WP12-S-N、WP22-A-N、WP22-B-N、WP05-N、WP06-N、WP02-N、WP01-N、WP07-N、WP08-V-N、WP08-T-N、WP24-N、WP26-A-N、WP26-B-N-Windows、WP27-A-N、WP11-N、WP22-C-N、WP13-A-N、WP25-R、WP25-N-Android、WP25-N-Windows、WP27-B-N、WP09-N 已完成且不重做；旧 WP20-W 未开工、已取消。多个包会修改 `storage.dart`、模型和字典，默认串行；不要让多个助手同时在同一工作区改共享文件。

| 阶段 | 领取顺序 | 交付目标 / 必要依赖 |
|---|---|---|
| V0.2-A 状态与术语 | WP20-N（已完成）→ WP21-N（已完成） | 保留完成/多选/展开契约；统一四象限名称和 AI 维度 |
| V0.2-B 核心交互 | WP03-N（已完成）→ WP04-N（已完成） → WP23-N（已完成） → WP12-S-N（已完成） → WP22-A-N（已完成） → WP22-B-N（已完成） → WP05-N（已完成） → WP06-N（已完成） → WP02-N（已完成） | WP03←WP20/21；WP04/23←WP03；搜索和日期入口←WP04。Android 与 Windows 同包适配 |
| V0.3-A 常用能力 | WP01-N（已完成） → WP07-N（已完成） → WP08-V-N（已完成） → WP08-T-N（已完成） → WP24-N（已完成） → WP26-A-N（已完成） → WP26-B-N-Windows（已完成） → WP27-A-N（已完成） | WP24←WP20/05；WP26←WP04/搜索；WP27-A←WP07 |
| V0.3-B 新字段与提醒 | WP11-N（已完成） → WP22-C-N（已完成） → WP13-A-N（已完成） → WP25-R（已完成） → WP25-N-Android（已完成） → WP25-N-Windows（已完成） → WP27-B-N（已完成） → WP09-N（已完成，V0.3-B 全部闭环） | 新任务字段依赖 WP11；提醒依赖 WP22；两平台提醒备份往返为发行前验收项 |
| V1.0 开源发行 | WP28-R → WP28-B → WP28-P（逐渠道） | Flutter Android/Windows、备份和 BYOK 冒烟通过；不等待后期扩展 |
| V1.1 可选服务 | WP29-R → WP29-S → WP29-C-N → WP29-P（逐渠道） | WP01 和发行渠道准备；独立后端不等于恢复 React 客户端 |
| 后续原需求 | WP10-N → WP12-T-N → WP13-R → WP13-N → WP14-N → WP15-R → WP15-N（日，再周）→ WP16-N；WP17/18/19 逐子批次 | WP10←WP20/05；标签/Today/导入/同步←WP11；Planner/庆祝←Today；开发模式←标签 |

每次只领取一个子批次，按下面的 2–3 项任务执行并验证，不把整个阶段塞进一个会话。父工作包的无后缀编号仍用于需求映射；所有客户端实施默认 N，共享 Flutter 实现。R 为研究/契约；S 为明确安排的服务端；P 为发布；平台插件包才分别列 Android/Windows。所有旧 W 派单停止。

Windows 的基础适配随每个包完成，不等手机功能全部结束再移植。WP03/04/23 检查窄/宽窗口和详情，WP12 检查搜索焦点与中文输入，WP05 检查鼠标移动，WP22 检查键盘日期操作。WP26 的托盘/全局快捷键后补，不阻塞基本桌面体验。

**UI 实验版的时机：** WP21-N、WP03-N、WP04-N、WP23-N、WP12-S-N、WP22-A/B-N 完成并通过两平台基础检查后，可领取第 10 节实验包；它不要求等到 Planner、云同步或收费全部完成。本轮不建分支。

## 4. 工作包（可以直接作为实施提示词）

下列文件路径均相对项目根目录。“新增”是建议实现落点，可依据现有命名作等价调整并记录，不代表文件已经存在。每包验收还须应用第 5 节通用验证规则。

### WP01-N · 服务商预设与动态模型发现

优先级 P1；M–L；无依赖；范围 MF10（含原 MF28）。**无当前 API 故障，不执行旧的故障排查任务。** 只派 WP01-N，共享 Flutter Android/Windows 实现下面 3 项。成功状态：选择服务商 → 只需输入 Key → 自动载入最新模型 → 使用自动选中的模型或点选其他模型；高级用户仍可自定义地址。

1. **预设与发现服务。** 文件：新增 `matrixflow-native/lib/ai_presets.dart`，修改 `matrixflow-native/lib/ai_service.dart`、`matrixflow-native/lib/models.dart`。首批列 DeepSeek、火山引擎、阿里云百炼及“自定义”；逐家查官方 Base URL、模型发现路径/分页/鉴权与可调用模型标识，记录在新增 `docs/AI_PROVIDER_PRESETS.md`。只内置端点及必要协议元数据，**不内置模型清单**。服务商 ID 与现有三协议枚举分离，旧配置可迁移成相应预设或“自定义”，不能仅靠模型名猜服务商。DeepSeek 使用 `https://api.deepseek.com` + `GET /models`，解析 `data[].id`；接口路径不能对所有厂商强制套 `/v1/models`。列表若是控制台目录而非可调用 ID，需适配；官方不提供 Key-only 发现时标注需手填模型/推理接入点，不假造列表。
2. **Key-only 配置交互。** 文件：`matrixflow-native/lib/screens/settings_screen.dart`、`matrixflow-native/lib/storage.dart`、`matrixflow-native/lib/l10n.dart`。默认选 DeepSeek，URL/协议放高级区；输入 Key 提交或失焦后自动获取一次，不逐字符请求；提供模型选择器、刷新、加载/空/失败状态及高级手填兜底。对相同配置复用内存缓存，Key/端点变化时失效；切服务商或退出页面取消旧请求，迟到结果不能覆盖新选择。切服务商不把原 Key 发往另一家，清空当前 Key 输入并取消已排队调用；第一版不用保存多家的 Key 档案。模型列表只来自网络响应，保留此前选中的模型；已有默认 `deepseek-v4-flash` 仅在返回列表包含它时优先选中，否则选择返回的首个可用文本模型并显示结果。这里保留一个已有默认偏好，不复制静态候选清单；若接口无能力元数据，不能假定列表中每个 ID 都能聊天。刷新失败保留此前有效选择，首次失败允许重试/手填。模型发现只校验发现能力，生成仍走现有请求流程。
3. **验证与交付。** 文件：`matrixflow-native/test/ai_regression_test.dart`、`matrixflow-native/test/widget_regression_test.dart`。mock 测试动态增删模型、重复/空 ID、分页、401/403/404/405/429、超时、迟到响应、切换端点不泄漏旧 Key。旧配置重启/导入不丢自定义 URL、模型、思考开关；生成参数依服务商能力适配，保留 DeepSeek 开/关行为，不无条件向新增服务商发送 DeepSeek 专用 thinking 参数。Android/Windows 检查网络错误反馈，不用公共代理转发 Key。完成：DeepSeek 从仅填 Key 到一次分类成功；火山/百炼分别记明支持程度和官方依据，未提供凭据时不声称实测通过。运行 Flutter 针对性回归和静态检查，分别记录 Android/Windows 实际运行范围；不派 WP01-W。

### WP02-N · 一键清空当前任务板的四个象限

优先级 P1；S–M；无依赖；范围 MF29。

1. **增加整体清空命令与入口。** 文件：`matrixflow-native/lib/storage.dart`、`matrixflow-native/lib/screens/matrix_screen.dart`、`matrixflow-native/lib/l10n.dart`。主界面菜单增加“清空此任务板”，确认框展示任务板名称与将删除的任务数。打开确认时捕获 boardId；一次状态更新删除该 board 四个象限所有父任务及其子项，包括已完成/被隐藏任务。保留任务板本身、其他 board、设置和 AI 配置；清理已选 ID、相关编辑状态，避免在途 AI/编辑结果把被清空的旧任务写回（按请求所属 board 与开始时的数据代次处理）。现有单象限清空可继续保留，但文案与整体清空区分。
2. **证明是真删除。** 文件：`matrixflow-native/test/bug_regression_test.dart`、`matrixflow-native/test/widget_regression_test.dart`。合成两块 board，各四象限混合完成/未完成/子任务，开启 hideCompleted。验证取消不变；确认后目标 board 的存储数组任务为零、已完成页为零、重启与导出为零；另一个 board 与设置不变；空板禁用/空态、重复操作幂等、确认中目标不漂移、异步结果不复活旧内容。完成：删除不是 completed=true，也不是归档转移。只用合成数据验证，不清理用户真实数据。

### WP03-N · 十字无框矩阵与紧凑任务行

优先级 P1；M；依赖 WP20/WP21；范围 MF01/MF06/MF07。只派 WP03-N，按交互复核文档第 3 节线框实施；单象限放大统一由 WP23 接线，本包不造另一套聚焦视图。

1. **共享 Flutter 布局。** 文件：`matrixflow-native/lib/widgets/task_card.dart`、`matrixflow-native/lib/widgets/quadrant_pane.dart`、`matrixflow-native/lib/screens/matrix_screen.dart`。去除象限圆角外框、任务白底卡片/阴影、子项竖线，仅中央一横一竖分隔四区域，编号和位置不变，四区独立滚动。完成图形约 20–22 dp、热区至少 48 dp，与正文首行对齐；正文约 16 sp/1.4 行高，矩阵最多 3 行，详情可看全。只保留完成、标题、截止信息和子项进度/展开入口，不常驻编辑/删除/添加子项行。普通态点行正文打开现有编辑器；方框仅完成，箭头仅展开，互不冒泡；多选态点正文只选择，工具栏“编辑”在仅选一项时可用。避免等待 WP04 才能编辑。新增按钮与批量栏移到矩阵外安全区；为 WP23 保留象限标题点击回调，不放未接线的假按钮。验证 360/390/412 dp、长中英日、深浅色、大字体、最后一条不被覆盖。
2. **Android/Windows 适配与验收。** 复用上述组件与必要的 `matrixflow-native/test/widget_regression_test.dart`。Windows 窄窗口不得挤压正文，鼠标/键盘能完成和编辑；Android 检查触摸热区、滚动、中文与键盘。控件不能仅在 hover 时才允许触摸设备编辑。完成：前后对照图能看出更多任务正文，完成/选择/拖动状态仍可辨认；多选模式任务行高度基本不变；原编辑/子项入口可用。不为纯颜色/分隔线新增镜像式测试，交互缺口才新增测试。

### WP04-N · 编辑父子任务、多行输入与弹层一致性

优先级 P1；M；依赖 WP20/WP03；范围 MF08/MF11/MF12/MF13 与 MF07 控件外移；回归 MF21/MF23。只派 WP04-N，不建立全局编辑模式。

1. **共享 Flutter 集中详情。** 文件：新增 `matrixflow-native/lib/widgets/task_detail_panel.dart`，修改 `matrixflow-native/lib/widgets/input_sheet.dart`、`matrixflow-native/lib/widgets/task_card.dart`、`matrixflow-native/lib/screens/matrix_screen.dart`，短文本仍复用 `text_prompt.dart`。点标题打开全宽底部详情，可上拉；宽屏且矩阵剩余宽度足够时显示右侧 320–360 dp 面板，否则仍用全宽。标题、父子列表、日期入口、象限、长期标记、拆解、删除集中在单个任务的详情里，复用同一业务命令。标题 Enter 换行、保存按钮提交；字段随内容增高至可视上限后滚动，键盘弹出仍可保存。任务板重命名保持单行。完成：不进入模式即可编辑父子项，日期/完成状态不因保存文字而丢失；新增与子项日期功能由 WP22 接入本面板。
2. **桌面操作与关闭一致性。** 文件：上述 Flutter 详情面板及 `matrixflow-native/lib/widgets/text_prompt.dart`。复用既有文字/日期命令，补齐父子编辑，不依赖双击/右键发现。Windows Ctrl+Enter 保存，Enter 换行，中文组词不误提交；窄窗口自动回到全宽详情，宽屏侧栏不遮住当前任务。遮罩关闭不静默丢草稿；内部空白只收键盘；返回/ESC/关闭保持同一规则。所有删除命令由详情或上下文工具栏明确触发并确认，详情加载的 taskId 失效后不能写回重建任务。
3. **回归。** 文件：`matrixflow-native/test/widget_regression_test.dart`。验证 1/5/20 行文本、自适应上限、中文输入法、键盘/返回/遮罩、关闭后重开；普通输入含空行的 3 条任务恰好新增 3 条；子项全完成与反选恢复按现有设置生效。完成：所有编辑入口可发现，关闭策略一致，控制器在退场动画中不提前释放。

### WP05-N · 手动换象限置顶与普通拖动

优先级 P1；S–M；范围 MF02/MF05；最好在 WP04 后执行。

1. **统一移动规则。** 文件：`matrixflow-native/lib/storage.dart`、`matrixflow-native/lib/widgets/input_sheet.dart`、WP04 的 `matrixflow-native/lib/widgets/task_detail_panel.dart`；必要时新增小型 Dart 任务命令模块。显式跨象限移动后，将该任务放到目标象限列表最前；下拉编辑与拖放共用此规则。不修改 createdAt 来伪造顺序；同象限操作不重排；其他任务和其他 board 相对顺序保持。当前数组顺序足够，不为此先引入排序数据库。截止日期自动升级仍按既有规则，本包不擅自改成手动置顶。验证移动、重启、导出再导入后的次序相同。
2. **验证手势与反馈。** 文件：`matrixflow-native/lib/widgets/quadrant_pane.dart`、`matrixflow-native/lib/screens/matrix_screen.dart`、`matrixflow-native/test/widget_regression_test.dart`。保留普通轻滑滚动、长按拖动；普通模式无需先点编辑，增加短提示/轻触觉与目标高亮。检查目标列表已经滚动时仍能看见移动结果，必要时收到任务后滚到顶端。Android 验证滚动/长按/取消拖动，Windows 验证鼠标拖放和移动菜单；一种输入方式通过不能代替另一种。完成：拖动不误触完成/编辑，取消拖动不变，移动不丢子项，Windows 鼠标可用。选择态多拖留给 WP10。

### WP06-N · 首次启动自动选择设备语言

优先级 P1；S；范围 MF09。

1. **默认值解析。** 文件：`matrixflow-native/lib/main.dart`、`matrixflow-native/lib/storage.dart`、`matrixflow-native/lib/models.dart`。只在没有有效保存语言时，从 Android/Windows 系统语言优先列表匹配 zh、ja、en；zh-CN/zh-TW 当前均映射现有中文，未支持语言回退 en。读取设备值的部分可注入以便测试。已有用户选 en 不能被当作缺省强行改中文。
2. **验证与完成。** 文件：`matrixflow-native/test/models_test.dart`、`matrixflow-native/test/widget_regression_test.dart`。验证新装 zh/ja/en/不支持语言、旧档明确 en、导入语言、后续手动改语言并重启。完成：首屏与设置文案一致，持久化和导入不覆盖用户已选值；本包不扩增字典支持范围。

### WP07-N · 已完成任务集中查看

优先级 P2；M；范围 MF14；回归 MF21。无需等待 WP11；第一版是已有 completed 数据的视图。

1. **数据与入口。** 文件：`matrixflow-native/lib/storage.dart`、新增 `matrixflow-native/lib/screens/completed_screen.dart`。提供“已完成”入口，默认当前 board，可切全部 board；列表展示来源任务板和象限。直接查询完成任务，不受 hideCompleted 影响，不复制任务，不伪造历史完成时间。无数据时有空态。
2. **恢复与验收。** 文件：`matrixflow-native/lib/screens/matrix_screen.dart`、`matrixflow-native/lib/l10n.dart`、`matrixflow-native/test/bug_regression_test.dart`。恢复调用既有父/子完成级联规则：恢复父任务后不能被“子项仍全完成”立即重新标完。验证完成→隐藏→已完成页可见→恢复→原板原象限可见，重启一致；全部 board 不泄漏为误删范围。完成：存档中已有完成任务自动可见，数据互通保持 v1；另设 archivedAt 或按完成时间排序需要后续模型包，第一版不做。

### WP08 · 宫格/列表视图与字体偏好

优先级 P2；M；依赖 WP03；范围 MF15/MF16/MF26。按 WP08-V-N（视图）、WP08-T-N（文字偏好）分别派单，每次完成下面一条的 Flutter 实现与两平台验收，不重画整个应用。

1. **视图切换（V）。** 文件：`matrixflow-native/lib/screens/matrix_screen.dart`、新增 `matrixflow-native/lib/widgets/task_list_view.dart`。宫格保留现有四象限；列表按象限分节共用任务卡和操作回调。viewMode 存为显示偏好，不复制或重排原始任务。验证切换后任务数、完成状态、编辑、筛选、移动、滚动位置正确；列表模式通过移动菜单可跨象限。完成：窄屏长标题可读，重启记住视图，两视图操作写同一份数据。
2. **字号与字体（T）。** 文件：`matrixflow-native/lib/theme.dart`、`matrixflow-native/lib/screens/settings_screen.dart`、`matrixflow-native/lib/models.dart`；显示字段接线按第 5 节同步。提供小/标准/大档及预览、恢复默认；字体提供系统字体与少量经许可核验且支持中英日的本地字体/字体栈。若需打包字体，新增 `matrixflow-native/assets/fonts/` 并更新 `matrixflow-native/pubspec.yaml`；缺字使用系统回退，不依赖启动联网下载。验证系统文字 1.0/1.3/2.0 × 应用字号，标题、弹层、设置、键盘按钮不被裁剪；不得直接禁用系统 TextScaler。完成：字号和字体即时生效、重启保留、导入有缺省兜底；未经许可验证的字体不纳入产物。

### WP09-N · 首次教程与可重复打开的帮助

优先级 P2；M；依赖 WP01/WP04/WP05/WP06/WP08/WP23/WP12-S；范围 MF04；复用 MF23。只介绍当前已落地入口，不等待 Planner、标签、托管服务或完整路线图；WP29 后再增一页服务选择说明。

1. **精简引导。** 文件：新增 `matrixflow-native/lib/screens/onboarding_screen.dart`；`matrixflow-native/lib/screens/matrix_screen.dart`。3–5 步说明普通添加按行拆分、长按移动、编辑/多选、AI 选服务商填 Key、已完成入口；可跳过、可返回，首次显示，不阻塞无 Key 使用普通待办。示例内容只在教程预览中展示，不注入真实任务。
2. **状态与验收。** 文件：`matrixflow-native/lib/storage.dart`、`matrixflow-native/lib/screens/settings_screen.dart`、`matrixflow-native/lib/l10n.dart`。完成/跳过状态作为本机引导元数据持久化；设置提供“重新查看教程”，导入旧备份不反复弹教程。验证新装、已完成、跳过、重开、语言切换、离线、键盘返回。完成：用户可独立完成添加→拖动→编辑，不需要先知道“编辑模式”含义。

### WP10-N · 多选任务批量移动

优先级 P2；M；依赖 WP20/WP05；范围 MF24。只派 WP10-N。使用 WP20 的选择高亮与上下文工具栏，不恢复双用途完成方框。

1. **批量命令。** 文件：`matrixflow-native/lib/storage.dart`，必要时提取 Dart 任务命令模块。新增 moveTasks(ids, targetQuadrant)，对当前 board 的有效 ID 去重，一次更新并持久化；按移动前显示顺序组成连续块放目标顶端。原本已在目标象限的选中项保持原位，只移动其他象限项；未选任务相对顺序不变。同一任务的子项不单独拖离父项。
2. **选择态手势与验收。** 文件：`matrixflow-native/lib/widgets/quadrant_pane.dart`、`matrixflow-native/lib/screens/matrix_screen.dart`。已选任务可发起集合拖动，反馈显示数量；提供“移动到”菜单作为触摸/键盘替代入口。保留编组功能，切 board、退出选择、成功移动后清理选择；取消不改变数据。验证选 2/20 条、跨多个来源象限、重复 ID、拖出窗口、空目标、含完成/子任务、重启顺序。完成：批量移动不变成逐条异步写入，拖动与复选不冲突。

### WP11-N · 新字段之前的数据兼容基础

优先级为后续功能的必要前提；M；不阻塞 WP01–WP10、WP20/WP21、WP22-A/B；WP22-C 的人工紧急性字段依赖本包。三个任务顺序执行；不是将整个存储系统重写。

1. **确定版本契约。** 文件：新增 `docs/DATA_COMPATIBILITY.md`，核对 `matrixflow-native/lib/models.dart`、`storage.dart` 与导入导出；冻结的 `types.ts` 仅作旧格式只读参考。区分本地 schema 与导出版本；为后续有用户价值的新字段采用明确的新版本（建议 ExportData v2），新 Flutter 读取 v1/v2，未知高版本拒绝覆盖。说明旧客户端不能理解新字段：当前旧 Native 拒绝非 v1，冻结的旧 Web 缺少同等版本门禁，**不能承诺新备份可安全导回旧 Web，也不为此继续修改旧 Web**。文档列新→旧、旧→新兼容矩阵；默认新格式与旧格式明确区分，若提供 v1 降级导出必须展示字段丢失提示。
2. **小型迁移与导入校验。** 文件：新增 `matrixflow-native/lib/data_migrations.dart`；修改 `matrixflow-native/lib/storage.dart`、`matrixflow-native/lib/models.dart`。迁移应可重复执行、失败不覆盖旧数据，先校验整份候选再更新状态；保留现有四个核心存储键及缺省兜底。新功能各自在本包框架下增加字段，不提前造齐未来所有模型。新 display/settings 字段也要走显式默认与导入白名单；控制器临时态/请求缓存不进入备份。
3. **旧版迁入与 Flutter 双平台往返测试。** 文件：新增 `matrixflow-native/test/fixtures/export-v1-minimal.json`、`matrixflow-native/test/fixtures/export-v2-minimal.json`、`matrixflow-native/test/data_migration_test.dart`。fixtures 为无密钥合成数据。验证 v1 升级、缺省字段、重复 ID/孤儿任务、损坏/未知高版本拒绝、失败后原始数据不变、迁移两次结果一致、旧 Web/v1→新 Flutter 迁入，以及新 Flutter Android→Windows→Android 字段保留（文件往返，不含自动同步）。完成：兼容矩阵有实际测试依据，不能宣称未经更新的旧客户端无损支持新字段。

### WP12 · 本地搜索先行，标签后续

范围 MF18。**WP12-S 为 P1、依赖 WP04、不依赖 WP11；WP12-T 为 P2、依赖 WP11/S。** 分别派 WP12-S-N、WP12-T-N，每次完成共享 Flutter 查询、入口和验证，不因新 tags 字段阻塞标题搜索。

1. **搜索与筛选（S）。** 文件：新增 `matrixflow-native/lib/task_query.dart`、`matrixflow-native/lib/screens/search_screen.dart`，修改 `matrixflow-native/lib/screens/matrix_screen.dart`。查询现有父/子标题，默认当前 board，可切全部 board；过滤象限、完成状态、截止日期（今天/本周/本月/逾期/无日期）。日/月用本地日历边界，本周为本地周一到下周一，非“过去七天”。全部本地查询，不引入后端；显式完成筛选优先于矩阵 hideCompleted 偏好，查询不改该偏好。命中子项时显示 board/父标题路径，点击打开原父任务详情并定位/展开子项；按 ID 去重，编辑/删除即时更新。退出保留原 board/视图/滚动，不因跨板查看悄悄切换批量清空目标；“前往任务板”才切板。验收：中英日/空查询/组合过滤/跨午夜/修改删除/跨板父子同名，合成 1,000 条任务记录响应；S 不造 tags/notes 字段。
2. **标签与备注查询接入（T）。** 文件：`matrixflow-native/lib/models.dart`、`matrixflow-native/lib/storage.dart`、`matrixflow-native/lib/task_query.dart`、任务详情。父任务级 tags 字符串数组，去首尾空格、空值和大小写等价重复；多个标签同时满足。WP13-A 后将父/子用户备注纳入关键词查询，不搜索历史 reasoning 或 Key。验证重启、v1 迁移、跨端往返、备注编辑及标签组合；过滤不改任务数据。备注接入可随 WP13-A 完成，不必等标签发布。

### WP13 · Markdown 备注与所见即所得编辑

优先级 P2；完整功能 L；依赖 WP11；范围 MF17。**先做 WP13-A-N 基础备注，再做 WP13-R → WP13-N 完整 Markdown。** Focus 的普通备注是参考下限，不把 Markdown/WYSIWYG 从原需求删除。

0. **基础备注（A，独立小包）。** 文件：`matrixflow-native/lib/models.dart`、Flutter 详情面板、`storage.dart` 导入白名单与 `task_query.dart`。父子任务均增加可选 `notesMarkdown` 字符串，先用普通多行编辑器原样保存，标题与备注分开；让用户能立即记补充信息。Markdown 作为交换文本，不执行 HTML，暂不声称可视编辑。不复用 reasoning，不默认发送 AI。验收：父子备注分别保存/清除、取消草稿、跨端往返、搜索可命中；后续升级编辑器保留既有内容和撤销预期。

1. **编辑器验证（R，仅选型与可丢弃原型）。** 文件：新增 `docs/MARKDOWN_EDITOR_RESEARCH.md`；原型放明确标记的 `experiments/markdown-editor/`。在 Flutter 生态比较至多两个维护中的候选，核对官方文档、许可证、IME、Android/Windows 支持、包体及 Markdown 往返。定义首版支持标题、段落、粗斜体、列表/清单、引用、链接、代码块；不支持结构必须保留原文，不静默损坏。完成：一组共同 fixture 完成 Markdown→可视编辑→Markdown 往返，写明取舍和 共享 Flutter 实施子计划和平台差异。未通过前不把依赖引入主工程。
2. **存储与编辑（WP13-N）。** 文件：`matrixflow-native/lib/models.dart`、新增 `matrixflow-native/lib/widgets/task_notes_editor.dart`、`matrixflow-native/lib/widgets/input_sheet.dart`、`matrixflow-native/pubspec.yaml`及对应锁文件。用独立 `notesMarkdown` 存用户备注，父项/子项都允许编辑；Markdown 为共享格式，不能仅导出某编辑器私有 JSON。可视编辑与源码模式可切换；正文不自动交给 AI、不恢复 reasoning 展示。验证中文组词、撤销重做、切换模式、长文滚动、取消/保存、跨端导入导出，HTML/脚本样例只作为文本或安全渲染。完成：真正可视编辑达标；只做预览时必须标为阶段产物，不能宣称已满足所见即所得。

### WP14-N · 今天待办页

优先级 P2；M；依赖 WP11；范围 MF20；只派 WP14-N。

1. **定义“今天”。** 文件：`matrixflow-native/lib/models.dart`、新增 `matrixflow-native/lib/planning.dart`。新增可空 `plannedDate`（本地日历日期 YYYY-MM-DD），与 deadline 分离。今天集合为手动计划在今天、今天有排程、截止今天的任务，按 taskId 去重；逾期任务单列，不悄悄改其 deadline。跨所有 board 展示来源；未安排且无截止的任务不自动塞入今天。完成状态由原任务提供，不能复制一套 TodayTask。
2. **页面与验收。** 文件：新增 `matrixflow-native/lib/screens/today_screen.dart`；Flutter 主页与字典。能从任意 board 加入今天/移出计划、定位原任务、编辑/完成；若因 deadline 或排程仍属于今天，移除手动计划后要说明仍保留的原因。验证跨午夜、前后台恢复、系统时区变化、到期与手动计划去重、父子不双计、历史完成任务不全部显示为今天完成。完成：集合算法可注入时钟测试，未来 WP15 加时间块不改变现有截止日期升级语义。

### WP15 · Planner 与 Schedule

优先级 P2；L；依赖 WP14；范围 MF19；拆 WP15-R → WP15-N（日，再周），首版不含重复任务、系统通知或外部日历同步。

1. **业务契约与参考评估（R）。** 文件：新增 `docs/PLANNER_DESIGN.md`；核对 `matrixflow-native/lib/planning.dart`。定义 Planner 为跨 board 待办池，Schedule 为日/周时间轴；时间块可引用 taskId，另可创建有标题的独立事件，使用独立 ID、起止时间、时区标识。删除任务时在同一次变更中移除其时间块，跨 board 来源改变后仍按 ID 关联；任务完成不删除过去的时间块。时段重叠提示但不强行禁止，结束必须晚于开始；全天计划使用 plannedDate，不伪装 UTC 午夜。参考 Super Productivity 的操作方式；它使用 Angular，本项目主线为 Flutter，直接嵌入其网页会增加 WebView 与第二套路由/状态/样式，首选独立参考交互，不为 Planner 恢复 React 产品线；任何候选代码复用另核验许可与跨平台价值。完成：数据、删除、跨日/DST、拖放语义与轻量日视图原型明确。
2. **时间块闭环（WP15-N）。** 文件：新增 `matrixflow-native/lib/screens/planner_screen.dart`、`matrixflow-native/lib/widgets/schedule_view.dart`；Flutter planning/model/store 按 R 契约接线。从任意 board 池拖到日程，支持点击选择时间作为替代；调整日期/长度，创建独立事件，从 Schedule 打开原任务，今天页反映排程。验证跨午夜、时区转换、重叠、删除、取消、切 board、重启与备份往返。完成：排期不是复制待办，所有入口展示同一事实；日视图完成后周视图另一个小批次，不能一次移植整个开源项目。

### WP16-N · 今日完成庆祝

优先级 P3；S；依赖 WP14；范围 MF22。

1. **触发规则。** 文件：`matrixflow-native/lib/planning.dart`、`matrixflow-native/lib/screens/today_screen.dart`。仅当当天非空集合由“有未完成”变成“全部完成”时触发一次；打开空页、过滤隐藏/删除最后一项不触发；子任务不另算总数。日期级已庆祝状态本地保存，反复勾选/重启不重复打扰。
2. **轻反馈与验收。** 文件：`matrixflow-native/lib/widgets/anim.dart`、Flutter 设置和字典。短动画/简洁文案，可关闭，尊重系统减少动画；无说教、无阻塞弹窗。验证 0→0、未完→全完、反选再完成、跨天、关开设置、减少动画模式。完成：最多一次轻反馈，不影响撤销完成和继续操作。

### WP17 · 从厂商系统笔记导入待办

优先级 P2；L；范围 MF03；先 WP17-R，再每厂商独立 WP17-厂商。第一目标小米 `com.miui.notes`，其余系统笔记不能按相同包结构假定兼容。

1. **可行性核验（R）。** 文件：新增 `docs/SYSTEM_NOTES_IMPORT_RESEARCH.md`。检查小米当前目标版本是否支持文本分享、结构化导出、公开且允许第三方读取的 ContentProvider/官方 API；记录 OS/App 版本、待办和普通笔记是否区分、标题/勾选状态/日期可获取程度。只做包/公开接口元数据检查及合成待办样例，不读取私有库、不申请 root、不以无障碍抓屏遍历用户笔记。包名本身只标识应用，读取还受接口导出与权限限制，见 Android 官方依据。其他厂商建立可行性表，不能承诺所有笔记都有可读取的待办接口。完成：给出“可直接授权读取 / 可分享或文件导入 / 无公开接口”证据与小米适配实施计划，阻塞项只限制对应适配器。
2. **可用入口实现（厂商子批次）。** 文件：新增 `matrixflow-native/lib/importers/system_notes_importer.dart`、`matrixflow-native/lib/screens/notes_import_screen.dart`；必要时 `matrixflow-native/android/app/src/main/AndroidManifest.xml` 与平台接收代码。Android 接系统分享/公开接口；Windows 可复用同一 Dart 文件/粘贴解析器，不实现手机私有接口。优先公开分享/导出/授权接口，先预览数量、来源、勾选状态、目标 board，再一次写入；按来源 ID 或内容指纹去重，可取消。若只能文本分享，明确丢失的结构字段，不能称“后台直读”。验证合成中文多行、完成态、重复导入、空分享、恶意/损坏文件、取消和备份往返。完成：小米有一条实测有效路径或有证据的接口限制报告；未验证厂商不显示“已支持”。

### WP18 · 可选网盘与文件同步

优先级 P3；XL；依赖 WP11；范围 MF25。**这是独立功能线，不是给导出函数加自动上传。** 按 WP18-R、WP18-Core、每个 Provider 分别派单；不引入自建业务后端。

1. **接口与同步契约（R）。** 文件：新增 `docs/SYNC_RESEARCH.md`。逐家核查 Dropbox、Google Drive、OneDrive、夸克、百度网盘、WebDAV 和用户选择的本地文件：公开 API、OAuth/PKCE 或其他授权、应用注册、Android/Windows 支持、条件写入/版本号、配额、后台限制。缺官方支持的网盘标记待定，不使用私有逆向 API。同步载荷默认仅任务/任务板和明确选择的非敏感偏好，**排除 AI Key 与网盘令牌**；现有完整备份含 Key，不能直接上传。定义对象 ID、修改版本/设备 ID、删除 tombstone、共同基线与冲突策略；同时编辑同一项时保留双方版本供选择，不能用“最近时间覆盖一切”。完成：确定一个最小可行传输适配器及安全的同步格式/恢复过程，给 Core 和该适配器写 2–3 任务实施子计划。
2. **核心与逐个适配。** 建议文件：`matrixflow-native/lib/sync/sync_engine.dart`；`matrixflow-native/lib/sync/providers/` 下独立文件、同步设置页；具体新文件清单由 R 固定。Core 先用两份 Dart 存储实例模拟离线 A/B 同改、删除冲突、任务板删除关联、重复重试、半文件写入、损坏文件和未知版本；通过后接一个真实传输。文件同步使用条件写入/原子替换或版本化快照等该平台实际支持的方式，不能假定 Android SAF 与 Windows 文件系统有相同原子 rename 能力。断网继续本地使用；失败显示状态并保留恢复副本，不静默覆盖。完成：双设备可重复验证收敛和冲突保留，重新授权不会擦本地数据；清空四象限的删除也同步正确。后续每家网盘独立补验收；localfile 可与第三方同步软件交换文件，但自研 P2P 发现/NAT 穿透另立研究项，不能把文件交换宣称为已实现 P2P。

### WP19 · 可选开发管理模式

优先级 P3；L；依赖 WP11/WP12；范围 MF27；分模式契约、Flutter N 实施。

1. **模式与 AI 契约。** 文件：新增 `docs/DEVELOPMENT_MODE_DESIGN.md`；`matrixflow-native/lib/models.dart`、`matrixflow-native/lib/ai_service.dart`。board 增加可选 mode，默认普通；任务增加 kind=feature/fix/other，与 quadrant 的重要/紧急维度独立。AI 对当前开发 board 的任务提出 kind、归类标题、象限建议；预览后应用，保留原任务 ID/子项/备注/日期，手动可改。先复用标签/分组，不造一套重复 Task 模型。完成：定义进度=已完成/总任务，避免混入未定义的故事点/工时指标。
2. **视图与验收。** 文件：新增 `matrixflow-native/lib/screens/development_board_view.dart`；Flutter 主页、设置、字典。每个象限内按 Feature/Fix/Other 分节，可折叠；关闭模式恢复普通矩阵，数据不丢。验证 AI 失败/取消保持原始任务、不同 board 模式独立、手工覆盖、批量移动、完成进度与双端导出往返。完成：管理模式能帮助分类和查看进度，不将“fix”一律当紧急，不额外引入 GitHub/Jira 同步。

### WP20 · 完成/选择分离、子任务展开、逐行删除线（N 已完成，W 已取消）

范围 MF30/MF31/MF36 与 MF01。**WP20-N 已于 2026-09-09 完成，代码 `747eb35`；WP20-W 未开工，因 React 冻结取消。不要重新领取。** 旧问题根因见 [交互复核第 1–2 节](UI_INTERACTION_REVIEW_2026-09-08.md)，后续 UI 包继承下面契约。

- 完成方框始终读 `task.completed`、调用既有父子完成命令；多选是正文点击、行高亮、已选标记、顶部数量的临时状态。切模式不改 completed；完成不同时选择或编辑。
- 子项有独立进度/展开箭头；按 `boardId/taskId` 保存会话展开状态，默认收起，切模式/切板保留；新增子项自动展开。展开不等于完成/选择；父任务隐藏不能留下孤儿子行。
- 多行删除线使用 `TextDecoration.lineThrough`，不在文本块中央画横条。父子级联、隐藏完成、任务 ID 与原始数据仍共用同一 Store。

落点：`matrixflow-native/lib/widgets/task_card.dart`、`anim.dart`、`quadrant_pane.dart`、`screens/matrix_screen.dart`、`l10n.dart` 及 `test/widget_regression_test.dart`、`test/bug_regression_test.dart`。历史验证：`flutter test --no-pub` 74/74，`analyze --no-pub` 0 issues；Android/Windows 新交互实机未测，不能写成实机通过。后续包修改这些交互时回归关键组合，不重复实现 WP20-N，也不对齐冻结 Web。

### WP21-N · 四象限名称与 AI 维度描述统一（已完成，自动化）

优先级 P1；S；范围 MF32。只修改 Flutter 共享实现，覆盖 Android/Windows；WP20-N 为已完成基线。本包不做十字布局、详情重构、日期新功能、服务商、后端或 UI 实验分支。**2026-09-09 已完成两项任务**，下一包 WP03-N。

1. **界面统一使用完整维度名。** 先核对 `matrixflow-native/lib/l10n.dart` 的 `q1Short`–`q4Short` 及所有调用点，重点 `lib/widgets/quadrant_pane.dart`、`lib/widgets/input_sheet.dart`，按实际调用补查 `lib/screens/matrix_screen.dart` 和编辑/移动入口。中文严格为 **Q1 紧急且重要、Q2 不紧急但重要、Q3 紧急但不重要、Q4 不紧急也不重要**；英文和日文表达相同两个维度。所有现有矩阵标题、移动/编辑选项、AI 预览统一，未来教程沿用字典，不提前造未存在页面。窄宽度可两行换行，不省略“不”，不用“马上做/计划做/授权做/不要做”替代完整名称。保持 Q1 左上/Q2 右上/Q3 左下/Q4 右下、现有 wire 值 1/2/3/4、历史任务 ID/象限不变；内部枚举和键名可保留，不扩大成迁移或全仓重命名。验收三语文字与四个维度逐一对应，360–412 dp 与 Windows 窄/宽窗口不丢否定词。
2. **提示词与必要回归。** 文件：`matrixflow-native/lib/ai_service.dart`、`matrixflow-native/test/ai_regression_test.dart`；必要时补 `test/widget_regression_test.dart` 或相关既有用例。删除分类定义中的行动括号建议 `(Do First)/(Schedule)/(Delegate)/(Don't Do/Delete)`，保留清晰的紧急/重要定义、输出 JSON/wire 契约、三协议、思考开关、分组和拆解能力。生活/娱乐任务不先验等同于“不值得做”，Q4 不输出说教/删除理由，不恢复卡片 reasoning。测试捕获真实请求构造中的提示词和三协议/思考参数，验证固定响应解析的四个象限不改值；mock 不证明模型分类准确率。无必要不发付费模型请求，不以历史 13 项样本宣称新提示词实测 100%。运行第 5 节 Flutter test/analyze，保留 WP20 的完成/多选/展开/删除线回归；记录未测 UI/真实模型。实现后同步 README/ARCHITECTURE 的当前名称说明、计划状态、HANDOFF 和 CHANGELOG；不改任何 React 应用文件。

### WP22 · 新建/父子日期入口与自动紧急性

优先级 P1；M（每子批次）；范围 MF33/MF34/MF35。**WP22-A-N、WP22-B-N、WP22-C-N 各自单独派单**，每批完成共享 Flutter 实现，避免日期 UI 与数据迁移混在一轮。A/B 依赖 WP04，不等待 Planner；C 的新持久化字段依赖 WP11。依据交互复核第 4 节执行。

1. **新建日期（A）。** 文件：`matrixflow-native/lib/widgets/input_sheet.dart`、`matrixflow-native/lib/screens/matrix_screen.dart`；`matrixflow-native/lib/l10n.dart`。普通添加与 AI 分类输入均加可选截止日期入口，今天/明天/选择日期/清除；公共日期应用于本次生成主任务，批量时注明范围，子项不默认继承。AI 提交时捕获日期/board/输入快照，取消或失败保留草稿，成功清空本次草稿日期；日期在 AI 运行中改变不能污染在途结果。验证无日期、普通单项/多行、AI 多项/分组、取消、空返回、切板、连续新增及重启；完成：选了日期的新任务落库后立即可见正确日期，未选日期不被补造期限。
2. **子项日期与全宽编辑（B）。** 文件：`matrixflow-native/lib/widgets/task_detail_panel.dart`、`matrixflow-native/lib/widgets/task_card.dart`、必要的 `storage.dart`。Native 子项由只改标题的 askText 升级为与父项一致的文字/日期表单，支持清除；数据沿用既有 SubTask.deadline。主/子日期相互独立，批量只影响明确选中的对象。验证父日期保留、子日期保存/清除、子日期晚于父日期、取消不变、完成/恢复不丢日期、导出到另一端再导回。完成：普通浏览点标题即可进入详情设置日期，无需先开“编辑模式”。
3. **阈值与人工优先（C，WP11 后）。** 文件：新增或抽取 `matrixflow-native/lib/deadline_policy.dart`；修改Flutter model/store、日期标签、设置与详情。统一日历天算法供标签/颜色/自动升级，移除 `_DeadlineChip <=2` 的独立“紧急”口径；说明“提前 N 天转为紧急（含当天），仅作用于有日期的未完成主任务”。无日期/已完成不移动；过期仍紧急；仅 Q2→Q1/Q4→Q3，重要性不变，不自动降级。Task 新增可选 `urgencyMode=auto|manual`，旧档与新增默认 auto；用户显式改变紧急维度后保存 manual，详情可恢复自动；仅改重要性不改模式，改日期不偷偷解除人工设置。验证 N/N+1、今天/昨天、跨月/年/DST、前后台/午夜、N 改动、子项不反向移动父项、手动移动后等待自动检查及重启仍不回跳、恢复 auto 可升级。字段走 WP11 的迁移与备份契约，并覆盖分组/编辑路径不丢字段。完成：日期解释、画面和后台规则一致，WP05 的手动置顶与本策略共存。

### WP23-N · 单象限聚焦与下方收起卡片

优先级 P1；M；依赖 WP03/WP04；范围 MF37；只派 WP23-N。**这与 WP08 的四象限纵向列表不同，必须单独验收。**

1. **视图和导航。** 新增 `matrixflow-native/lib/widgets/quadrant_focus_view.dart`，修改 `screens/matrix_screen.dart`、`widgets/quadrant_pane.dart`。点象限标题后，选中象限在主区域全宽显示任务；其他三个按原编号顺序缩成下方三张简洁卡片，只显示完整名称和数量，空象限也保留。点击收起卡切换主象限；返回恢复矩阵/列表及原位置。任务完成、展开、编辑共用已有回调，任务行不复制数据；视图状态按 boardId/象限保存本机会话滚动，切 board 不串状态，删除 board 清理缓存。手机键盘/横屏/大字号下仍能返回与切象限，下方卡片不能被 FAB 遮挡。
2. **操作与验收。** 原始四象限仍存在；聚焦状态仅改变展示，不能改 quadrant/boardId 或隐藏真实任务。顶部显示当前板名与返回，多选语义沿 WP20。WP05 后下方卡可作同板拖放目标，并保留“移动到”菜单；过滤/隐藏完成时计数使用与主矩阵相同口径。验证四区各有/空、最后一项完成隐藏、子项展开、切板返回、移动、恢复滚动、弹详情返回；交付截图须同时可见主象限和下方三个卡片，普通全宽列表不算完成。

### WP24-N · 滑动操作、撤销与轻量反馈

优先级 P2；M；依赖 WP20/WP05；范围 MF38；只派 WP24-N。沿现有稳定 ID 和移动命令实现，不照搬 Focus 的状态/存储逻辑。

1. **手势与命令。** 修改 `matrixflow-native/lib/` 下的 `widgets/task_card.dart`、`widgets/quadrant_pane.dart`、`storage.dart`，建议新增 `task_commands.dart`。普通态横滑完成/恢复、反向滑动删除，纵向滚动、长按拖动、点完成/编辑互斥；多选态关闭滑动。提供同等可见菜单操作和 5 秒撤销条；一次删除本任务连同子项，立即持久化，仅在短撤销窗口保留该命令需要的快照，不存整板回滚副本。撤销完成只恢复本命令涉及的父子状态，撤销删除回原 board/顺序；目标板被删、任务已被其他命令修改时不能覆盖新结果或复活旧板。整板清空继续 WP02 的确认语义，不复用单项滑动。
2. **反馈与验证。** 新增必要 `test/task_commands_test.dart`；轻振动、减少动画偏好接 Flutter 设置/默认/字典（Windows 无振动时平静降级，保留可见菜单反馈），尊重系统减少动画。完成/恢复/删除/移动提示只陈述动作，无象限说教；撤销不是完成提示的一段假文案。验证撤销/超时、连续两次删除、切板、关闭页面、重启、父子级联、清空后在途 AI、不完整拖动；重启不恢复已删项，撤销不覆盖后续编辑，完成隐藏后仍可用撤销条恢复。

**撤销失效契约：** 记录 board 数据代次或等价的冲突标记。整板清空、单象限清空和覆盖导入必须使相应旧撤销记录失效，不能仅检查 board 是否还存在。分别验证“滑删→整板清空→撤销”“滑删→清空原象限→撤销”“滑删→覆盖导入→撤销”，不得复活已清空或被新备份替换的内容；与 WP02 的在途 AI 失效规则使用同一事实来源。

### WP25 · 可选本地日期时间提醒

优先级 P2；L；依赖 WP11/WP22；范围 MF39。拆 WP25-R、WP25-N-Android、WP25-N-Windows；通知不是 Planner 的前置条件。

1. **契约与适配验证（R）。** 新增 `docs/REMINDERS_DESIGN.md`；核对 Flutter 通知插件官方支持、Android/Windows 打包要求和权限。主/子任务增加可空 `reminderAt`（明确时刻）及必要时区信息；deadline 仍是截止日，plannedDate 仍是计划日，不能互相替代。默认无提醒，设置日期不强行开启通知、不按象限补造截止日。明确过去时间、时区改变、重启恢复和错过提醒的规则；首版不自动补发一堆过期提醒。
2. **原生接线与验收（按平台分别）。** 建议新增 `matrixflow-native/lib/services/reminder_service.dart`，修改 `models.dart`、`storage.dart`、详情、新建入口、`pubspec.yaml` 及对应平台清单。用户选择提醒时才请求权限；拒绝仍保存任务并显示提醒不可用。稳定映射 board/task/subtask 到通知 ID；新增/改期/完成/删除/整板清空/导入/恢复都统一重排或取消，不依赖 Widget 留在内存。通知点击在冷启动/后台正确定位原板和父子项，任务已删除则友好退出。权限不足、精确调度不支持不得承诺准点；能关闭提醒。用合成数据测改期不双响、完成删除不再响、重启、时区和权限拒绝，分别记录 Android/Windows 实测范围。
3. **共享字段与平台差异验收（随两个 N 子批次完成，不另派 Web）。** Android/Windows 共享模型、详情与备份，不因某平台无法调度而丢弃提醒字段；导入不等于获得通知权限。分别测试可用权限和实际调度能力，未验证平台标为待验。不能借 WP29 默认上传任务来代替本地提醒；不更新冻结 Web 的提醒 UI 或模型。

### WP26 · Windows 效率与应用内命令面板

优先级 P2；L；依赖 WP04/WP12-S；范围 MF40。WP26-A-N 先做应用内命令，WP26-B-N-Windows 只做 Flutter Windows；不扩展 Tauri/Capacitor 第二套桌面/手机实现。

1. **应用内快捷操作（A）。** 建议新增 `matrixflow-native/lib/widgets/command_palette.dart`、`lib/shortcuts.dart`。复用本地搜索，提供创建、搜索、切 board/象限、聚焦/返回、显示已完成、设置、快捷键帮助；桌面 Ctrl+K 打开、Esc 返回。中文组词与文本输入中的原生快捷键优先，不拦截系统或文本编辑的原生操作；所有命令有按钮替代，不靠记快捷键使用应用。验收命令定位跨板原任务、空数据、焦点返回、子项打开、输入法和无键盘触摸。
2. **Windows 壳（B）。** 建议新增 `matrixflow-native/lib/services/desktop_shell_service.dart`，修改 `main.dart`、`pubspec.yaml`、`windows/runner/` 必要文件。选型前核验插件官方维护和平台支持。托盘提供显示、快速添加、搜索、真正退出；“关闭到托盘”显式可选且默认关闭，首次启用解释如何退出；可配置全局唤起快捷键，注册冲突不导致启动失败，退出时释放。隐藏/恢复保留任务与 board，不生成重复窗口；最小化不终止正常本地提醒。验收 release 托盘图标、系统焦点、快捷键冲突、窗口恢复、退出后台进程消失，Android 不加载桌面插件调用。

### WP27 · 当前进度与完成历史

优先级 P2；M；范围 MF41。WP27-A-N 依赖 WP07、无需迁移；WP27-B-N 依赖 WP11，均使用共享 Flutter 实现。沿用多 Board，不造重复的统计任务表。

1. **当前统计（A）。** 建议新增 `matrixflow-native/lib/task_stats.dart`；主页/聚焦页/已完成页显示当前板未完、已完、逾期和完成比例，可切全部板并标清范围。默认按父任务计数，子项进度独立显示，避免父子双计；隐藏已完成只改任务可见性，不歪曲统计；零任务不显示虚假的 100%。使用现有 completed/deadline，不能标作“今天完成”。验收多板、隐藏、筛选、子项自动完成、删除、整板清空后统计同步。
2. **最近完成与按日（B）。** 在 Task/SubTask 中新增可空 `completedAt`，仅未完成→完成写当前时间，重复设置不重记，反选清空；旧已完成任务时间未知，不借 createdAt 或导入时间伪造。沿 WP11 接入 Flutter 创建/编辑/批量/AI/导入路径，WP24 撤销保留正确旧值。统计定义为“当前仍已完成任务的完成日期分布”，不是永久累计生产力；删除后不保留事件历史，日后要审计历史另立包。最近完成允许查看来源板并恢复。验收跨午夜、父子自动完成只算一次、反选再完成、历史无时间记录和跨端往返。图表非必需，先用清晰计数/列表。

### WP28 · 独立开源与应用商店发行

发行必需；L；范围 MF42。按 WP28-R（准备）、WP28-B（构建）、WP28-P（逐渠道发布）派单；不要求用户先找几十人试用。正式客户端目标仅 Flutter Android/Windows；React/Tauri/Capacitor 冻结保留，介绍/下载页可另行提供，不上线第二套待办主线。

1. **发布准备（R）。** 新增 `docs/RELEASE_PLAN.md`，整理 README、许可证候选、依赖/字体/图标来源、更新日志、演示与隐私说明。推荐独立客户端 MIT 为候选，正式发布前确认权利与用户选择；此次不新增 LICENSE 或复制 Focus 素材。定义应用名/包名、版本号、更新来源和逐渠道清单：GitHub Release、Android 首个商店，Windows 先 Release 再按需商店。核验实际目标商店当时要求、主体/签名/支付能力，缺主体或渠道材料只限制该渠道，不阻塞本地版或 GitHub 准备；不预设已经具备资质。
2. **构建与可安装产物（B）。** 文件：`matrixflow-native/android/app/build.gradle.kts`（若实际为 .gradle 则用实际文件）、Android/Windows 图标与配置、CI 配置（新增时放 `.github/workflows/`）及发布文档。正式签名通过本机/CI 凭据提供，不提交密钥；验证旧版原位升级保留任务、备份往返、Android 目标设备兼容、Windows 干净环境启动与两平台共享备份；不为本包运行 React 构建。生成校验和和可追溯版本；GitHub 下载包与商店包的签名/更新路线明确。自动化和有代表性的设备冒烟可由助手执行，未实测平台不得标绿。
3. **逐渠道发布（P）。** 先准备可审核的源码范围、README/截图、隐私说明、发布说明和具体安装包，再在用户交给发布任务的目标账户/渠道操作。没有确定远端、账户或商店时交付准备产物与缺项，不虚构发布。源仓库如保留 React 源码须明确标注 legacy/frozen，不能宣传为同版本功能；不为归档标识搬动目录。源仓库发布不携带用户备份、Key、服务端凭据或签名材料；本地任务免费、AI 数据发送范围、BYOK 和托管版的区别写清。托管版尚未上线时不得出现可扣款的空按钮，WP29 上线后再更新商店资料。

### WP29 · ¥9/月可选托管 AI

发行后；L；依赖 WP01 和 WP28 对应渠道准备；范围 MF43。**客户端开源且保留 BYOK；服务端是独立运营组件，不必随客户端一起公开；本轮仅规划，不搭服务器或收费。** 推荐复用 TypeScript 做小型服务，单机阶段用独立持久化账本即可；不引入微服务或把本地任务迁库。

1. **服务契约（R，独立计划包）。** 新增 `docs/HOSTED_AI_DESIGN.md`，确定账号登录、订阅周期、额度、退款/取消、故障和超额文案。采用 ¥9/月、100 点/月作为首版草案；按输入/输出上限定义标准请求点数，复杂拆解显示预计/最大扣点，失败不向用户扣点，供应商已消耗的失败请求计入运营成本。账号状态、订单、权益、幂等请求与额度账本在服务端；任务库仍在客户端。必须先用合成任务校准合理的输入/输出限制，不为了压到 800 tokens 截断正常任务。2026-09-09 重核 [DeepSeek 价格](https://api-docs.deepseek.com/zh-cn/quick_start/pricing/) 与昨日相同，100 个输入 2,000/输出 800 tokens 的高峰请求加 20% 冗余约 ¥1.58；只是定额基准，不是盈利承诺。周期按支付权益时间，不以客户端时钟发额度；续费/恢复登录不重复赠点。完成：成本封顶、消费者能理解的额度和请求/账本示例一致，再细化 S/C/P 各批任务。
2. **服务端（S）。** 建议新增独立 `server/`，落点 `src/auth.ts`、`src/entitlements.ts`、`src/ai.ts`、`src/db.ts` 和对应集成测试；实施前按 R 收敛，不一次写全部支付功能。仅代理本产品分类/分组/拆解业务，不开放任意 URL/模型透传。服务商 Key 只在服务端，校验登录、有效权益、文本长度/输出上限、并发和账号/整体预算；额度预留→请求→成功结算或失败释放用事务与幂等请求 ID，双击/超时重试/并发不能多扣或绕限。取消后的上游费用有清楚处理；请求日志不存待办正文或 Key。服务器异常和运营 Key 额度耗尽返回可理解错误，不损坏客户端草稿。本批用测试权益和 mock 供应商证明越权、并发、重放、崩溃恢复/对账、超限与失败路径，不开放生产收费。
3. **客户端接入（WP29-C-N）。** 新增 `matrixflow-native/lib/hosted_ai_service.dart`，修改 Flutter AI 配置/设置/请求入口，必要时新增订阅页。设置提供“自带 Key / 省心服务”，默认不覆盖老 BYOK 配置；托管选择固定运营端点，不索取用户供应商 Key。登录显示权益/剩余点、调用前确认复杂请求计点、失败保留输入；切模式或退出登录取消旧请求，迟到响应不能跨账号/board 写入。无网络、无订阅、到期都能用普通待办；用户可随时回 BYOK。登录令牌/订阅权益不进入 ExportData，不能通过导入 JSON 伪造权益；Flutter 登录令牌用 Android/Windows 对应的平台安全存储，不新增 React 登录实现。验收 BYOK/托管两种 AI 模式切换、过期/超限、登录恢复、备份不带令牌、无订阅本地功能全可用。
4. **支付与运营上线（P）。** 在 R 确认的实际渠道实现订单、服务端验签/回执验证、重复通知幂等、取消/退款与权益回收，不能相信客户端“支付成功”；每渠道独立适配，不假定各商店允许同一种外部支付。先完成沙箱订单→权益→扣点→退款闭环和账本备份恢复，再部署 HTTPS 服务、设置监控/成本告警与运营总额熔断，明确支持联系和停服处理。账号额度与本地任务彻底分开，停服不锁任务。商店/支付账户信息缺失时只交付可审阅结果与必要缺项；不拿真实用户付款做测试。首版不开不限量、广告补贴或默认云同步。

## 5. 每包验证与交付规则

- **开工**：读取 `AGENTS.md`、`docs/HANDOFF.md`、本计划第 1/3/5 节和领取包；`git status --short` 保护已有改动，只加载涉及源码。不重做全工程审查，不修 B01，不全仓格式化。
- **客户端范围**：只改 `matrixflow-native/` 与必要文档。React/Tauri/Capacitor 不做功能对齐，`types.ts`、`App.tsx`、`translations.ts` 等保持冻结；WP29 后端与独立介绍页须按各自子批次明确范围，不能由 Flutter 包顺带实现。
- **新增设置/数据**：同步 Flutter `models.dart`、`storage.dart` 默认/加载/导入白名单、设置页、`l10n.dart` 三语。可忽略的可选显示偏好可保留 v1；任务信息新增字段必须经过 WP11。保留旧 v1→新 Flutter 的迁入，不承诺未来字段回写旧 React；新 Flutter Android/Windows 文件往返一致。
- **逻辑验证**：先跑最相关单元/Widget 用例；子批次完成时，在 `matrixflow-native/` 运行 `D:\Dev_SDKs\Flutter_SDK\bin\flutter.bat test --no-pub` 与 `D:\Dev_SDKs\Flutter_SDK\bin\flutter.bat analyze --no-pub`。新增依赖或尚未解析依赖时先 `flutter.bat pub get`。不因 Flutter 包跑 `npm run build` / `npx tsc --noEmit`；仅另行明确的 legacy 修复任务才用 Web 命令。WP29 服务端测试按届时技术栈单列。纯文档调整不运行应用测试。
- **UI 验证**：Android 360–412 dp、触摸/软键盘、长中文、浅深色和大字体；Windows 鼠标/键盘、中文 IME、焦点返回、窄/宽窗口。用合成多 Board 数据覆盖共享行为；不允许退化单板，不以 Android 成功冒充 Windows 成功。低风险图标/配色不新建镜像测试；交互变化补有价值回归。未测设备或真实服务须写明最短待测步骤，不要求招募几十人。
- **构建**：核心基础流程完成时，或平台插件/依赖变化时，使用上述 SDK 跑 `flutter.bat build apk --release --no-pub` 与 `flutter.bat build windows --release --no-pub` 各一次。不为每个文字/图标包反复打包；默认 `flutter test` 不含设备集成测试。历史 74/74 和 release 成功不代替新场景验收。
- **证明**：仅用合成任务/无密钥 fixtures；不删除、覆盖或上传用户真实数据作为测试。不把真实备份、API Key、令牌放到文档、日志或提交。mock 请求契约不证明真实模型分类准确率。
- **交付**：记录需求 ID/子批次、改动文件、实际命令与结果、未测项、限制和下一包。更新本计划第 9 节及 HANDOFF；只有代码/功能实际改变才追加 CHANGELOG。遵循会话提交授权，不夹带他人改动。
- **停止**：完成所领子批次即交接，不自行展开整个阶段。接口不可行时交付证据与最小可行替代；取消的 W 不登记为完成，规划不登记为上线。

## 6. 历史代码核对依据（只读参考，不是派单清单）

以下表格保留 2026-09-08 静态走查位置；含旧 Web 路径和 WP20-N 之前的状态，不代表当前仍须修改。执行范围以第 1/3/4/5/9 节为准，WP20-N 已完成。

| 结论 | 入口 |
|---|---|
| 首屏语言缺省 en | `App.tsx:140/197`；`matrixflow-native/lib/models.dart:265` |
| 手动移动未置顶 | `App.tsx:364` 的 handleDrop；`matrixflow-native/lib/storage.dart:238` 的 moveTask；编辑更新也需接入 |
| 已有逐象限清空，不等于整体清空 | `App.tsx:381/398`；`matrixflow-native/lib/widgets/quadrant_pane.dart:232`；`matrixflow-native/lib/storage.dart:253` |
| 已有普通模式长按拖动 | `matrixflow-native/lib/widgets/quadrant_pane.dart:171`；`matrixflow-native/test/widget_regression_test.dart:233` |
| 选择态禁用拖动 | `components/TaskCard.tsx:80`；`matrixflow-native/lib/widgets/quadrant_pane.dart:173` |
| 标题与复选框竖排、子项竖线 | `matrixflow-native/lib/widgets/task_card.dart:57/128`；Web 子项与分组编辑区域也有竖线 |
| 多行输入部分已有 | `components/InputArea.tsx:30/68`；`App.tsx:1373`；`matrixflow-native/lib/widgets/input_sheet.dart:81/517`；`matrixflow-native/lib/widgets/text_prompt.dart:48` 仍单行 |
| 换行批量添加/父任务自动完成已有 | `App.tsx:666/686`；`matrixflow-native/lib/widgets/input_sheet.dart:166`；`matrixflow-native/lib/storage.dart` 更新逻辑与已有回归用例 |
| 模型发现可复用网络层 | `services/aiService.ts:273`；`matrixflow-native/lib/ai_service.dart:145` 目前是探测状态，尚未提供模型选择列表 |
| 遮罩关闭部分已有 | `components/ui/Modal.tsx:82`；Flutter showDialog/showModalBottomSheet 调用 |
| 数据演进基础尚缺 | `types.ts`、`matrixflow-native/lib/models.dart` 为 ExportData v1；旧 Web 导入版本门禁与 Native 不同 |

## 7. 外部参考与尚未验证的范围

- DeepSeek 官方列模型接口为 `GET /models`，数据在 `data[].id`；官方 Base URL 是 `https://api.deepseek.com`。所以本计划采用完整发现地址 `https://api.deepseek.com/models`。用户提到的 `/v1/models` 作为兼容路径待实现时验证，本轮未用用户 Key 发请求。[模型列表](https://api-docs.deepseek.com/api/list-models/)、[首次调用](https://api-docs.deepseek.com/)
- 服务商预设交互参考用户指定的 [Cherry Studio](https://github.com/CherryHQ/cherry-studio) 与 [Chatbox](https://github.com/chatboxai/chatbox)。本轮只核对仓库入口，尚未审阅具体适配器；下一轮按需读取有关文件和许可证，优先独立实现交互与注册表，不直接搬运整套客户端。
- 用户提供的 Super Productivity 地址已重定向到 [当前仓库](https://github.com/super-productivity/super-productivity)。其 [package.json](https://raw.githubusercontent.com/super-productivity/super-productivity/master/package.json) 显示 Angular 构建体系，仓库提供 [MIT LICENSE](https://raw.githubusercontent.com/super-productivity/super-productivity/master/LICENSE)。本计划关于直接嵌入成本的判断是结合双方技术栈的工程推断；真正复制具体文件前仍需核对文件和依赖许可、保留所需声明。
- Android 对 ContentProvider 的访问受接口与权限约束；系统文件选择器允许用户选择共享文档，不等于任意读取其他 App 私有待办库。因此包名 `com.miui.notes` 不能单独证明可直读。[ContentProvider 基础](https://developer.android.com/guide/topics/providers/content-provider-basics)、[Storage Access Framework](https://developer.android.com/training/data-storage/shared/documents-files)
- 火山/百炼模型发现 API、小米待办公开接口、各网盘授权可行性、Markdown 编辑器选型，均属于对应工作包的待验证项。本轮没有把这些外部能力标成已支持。
- 本轮新增用 gh 与网页核对的历史案例、Focus/Einsen/Tasks.org 候选、Super Productivity 已合并移动 UI 修复，以及静态状态根因，集中见 [交互复核与设计决策](UI_INTERACTION_REVIEW_2026-09-08.md)。关闭的讨论与已实现修复分开记录。

## 8. 可复制的接手提示词

```text
接手 D:\Dev_project\martix，只实施 docs/IMPLEMENTATION_PLAN_2026-09-08.md 的 WP11-N。先读 AGENTS.md、本 HANDOFF、计划第 1/3/5 节和 WP11-N。

Flutter Android/Windows 是唯一持续开发客户端；旧 W 指 React Web。先 git status 保护未提交文档。不改 React，不重做 WP20-N/WP21-N/WP03-N/WP04-N/WP23-N/WP12-S-N/WP22-A-N/WP22-B-N/WP05-N/WP06-N/WP02-N/WP01-N/WP07-N/WP08-V-N/WP08-T-N/WP24-N/WP26-A-N/WP26-B-N-Windows/WP27-A-N。

本包只做新字段演进与迁移契约：更新 models.dart 与 storage.dart；规范未来任务与设置新字段的序列化、缺省兜底、兼容读取旧版 ExportData v1，保证备份互通与版本演进；保持本地核心四键不变。

用 D:\Dev_SDKs\Flutter_SDK\bin\flutter.bat 在 matrixflow-native/ 跑 test --no-pub 与 analyze --no-pub。182/182 是 V0.3-A 基线。未测实机写明。完成后交接后续，停止。
```

## 9. 派单状态

截至 2026-09-15 WP22-C-N 实施。

| 包 / 事项 | 状态 | 证据 / 下一步 |
|---|---|---|
| Flutter 主线 / React 冻结的计划切换 | 已完成（文档） | 本计划、HANDOFF、AGENTS 与已采纳 ADR 同步；无目录移动 |
| WP20-N | 完成（自动化） | `747eb35`；当时 Flutter test 74/74 |
| WP20-W | **取消，未开工** | 不再要求对齐冻结 Web |
| WP21-N | **完成（自动化）** | 完整维度名 + 分类提示词去行动括号；`flutter test --no-pub` 77/77，`analyze --no-pub` 0 issues；实机与真实模型未测 |
| WP03-N | **完成（自动化）** | 十字无框矩阵与紧凑任务行；`flutter test --no-pub` 80/80，`analyze --no-pub` 0 issues；实机未测 |
| WP04-N | **完成（自动化）** | 编辑父子任务、多行输入与弹层一致性（集中详情面板）；`flutter test --no-pub` 86/86，`analyze --no-pub` 0 issues；实机未测 |
| WP23-N | **完成（自动化）** | 单象限聚焦与下方收起卡片；`flutter test --no-pub` 90/90，`analyze --no-pub` 0 issues；实机未测 |
| WP12-S-N | **完成（自动化）** | 本地搜索与筛选先行（标题与子项关键字本地搜索）；`flutter test --no-pub` 104/104，`analyze --no-pub` 0 issues；实机未测 |
| WP22-A-N | **完成（自动化）** | 普通/AI/批量新建任务支持设置截止日期与快照隔离；`flutter test --no-pub` 107/107，`analyze --no-pub` 0 issues；实机未测 |
| WP22-B-N | **完成（自动化）** | 子项日期与独立编辑表单；`flutter test --no-pub` 110/110，`analyze --no-pub` 0 issues；实机未测 |
| WP05-N | **完成（自动化）** | 手动换象限置顶与普通拖动（跨象限置顶、相对次序保持、右键移动菜单、滚动目标平滑回顶）；`flutter test --no-pub` 114/114，`analyze --no-pub` 0 issues；实机未测 |
| WP06-N | **完成（自动化）** | 首次启动自动选择设备语言（系统语言优先匹配 zh/ja/en，zh-CN/zh-TW 映射中文，未支持回退 en，已有明确选择不覆盖）；`flutter test --no-pub` 128/128，`analyze --no-pub` 0 issues；实机未测 |
| WP02-N | **完成（自动化）** | 一键清空当前任务板四个象限（菜单清空入口、任务数与名称确认弹窗、原子清空全四象限/完成/隐藏任务、保留其他看板/设置/配置、重置选中/详情/聚焦、代数追踪防在途 AI 复活、导出与重启一致）；`flutter test --no-pub` 133/133，`analyze --no-pub` 0 issues；实机未测 |
| WP07-N | **完成（自动化）** | 已完成任务集中查看（直接查询 completed 数据、不受 hideCompleted 影响、父子级联恢复防 autoCompleteParent 误判、CompletedScreen 看板/象限展示与单任务安全删除、MatrixHome 头部入口图标）；`flutter test --no-pub` 144/144，`analyze --no-pub` 0 issues；实机未测 |
| WP08-V-N | **完成（自动化）** | 宫格/列表视图切换（V，TaskListView 纵向四象限分节、显示偏好持久化、操作栏一键切换、紧凑按钮防窄屏溢出）；`flutter test --no-pub` 149/149，`analyze --no-pub` 0 issues；实机未测 |
| WP08-T-N | **完成（自动化）** | 字号与字体偏好（T，FontSizePref/FontFamilyPref、CombinedTextScaler 继承 TextScaler 复合系统与应用缩放、设置页动态排版预览与恢复默认）；`flutter test --no-pub` 154/154，`analyze --no-pub` 0 issues；实机未测 |
| WP24-N | **完成（自动化）** | 滑动操作、撤销与轻量反馈（TaskUndoSnapshot 任务深拷贝与索引快照、5 秒浮动撤销 SnackBar、多选关闭滑动、右键次级菜单、轻触觉反馈、清空看板/象限/覆盖导入代数失效契约）；`flutter test --no-pub` 166/166，`analyze --no-pub` 0 issues；实机未测 |
| WP26-A-N | **完成（自动化）** | Windows 效率与应用内命令面板（A，shortcuts.dart 快捷键体系与 EditableText 焦点让位、CommandPaletteDialog 模糊搜索命令与跨看板任务跳转、三语文案）；`flutter test --no-pub` 172/172，`analyze --no-pub` 0 issues；实机未测 |
| WP26-B-N-Windows | **完成（自动化）** | Windows 壳集成与托盘（B，DesktopShellService 非桌面平台安全 no-op、托盘菜单、关闭到托盘设置 closeToTray、热键冲突安全捕获）；`flutter test --no-pub` 176/176，`analyze --no-pub` 0 issues；实机未测 |
| WP27-A-N | **完成（自动化）** | 当前进度与完成统计条（A，computeTaskStats 纯计算模型、父子任务计数严格独立、0% 针对空数据安全兜底、TaskStatsBar 响应式流式布局防溢出、当前/全部看板范围切换）；`flutter test --no-pub` 182/182，`analyze --no-pub` 0 issues；实机未测 |
| WP11-N | **完成（自动化）** | 数据版本迁移与导入格式演进契约（新增 DATA_COMPATIBILITY.md、data_migrations.dart，ExportData v2 标准与 v1 兼容读取/降级导出，整份校验原子回滚，跨端 100% 往返无损）；`flutter test --no-pub` 197/197，`analyze --no-pub` 0 issues；实机未测 |
| WP22-C-N | **完成（自动化）** | 截止日期自动调整紧急性算法统一与人工覆盖（新建 deadline_policy.dart 统一本地时区午夜日历天对齐、Task.urgencyMode 人工覆盖与 WP11 v2 持久化/v1 剥离、跨紧急维度操作标记 manual、详情面板已手动调整提示与恢复自动按钮、设置页动态天数文案、task_card 移除硬编码 <=2）；`flutter test --no-pub` 219/219，`analyze --no-pub` 0 issues；实机未测 |
| WP13-A-N | **完成（自动化）** | 基础纯文本备注（Task/SubTask 可选 notesMarkdown 独立字段、普通多行编辑器原样保存、子项编辑弹窗备注与列表摘要、task_query 纳入关键词搜索、严格排除 reasoning 与 API 密钥、WP11 v2 导出与 v1 降级剥离）；`flutter test --no-pub` 223/223，`analyze --no-pub` 0 issues；实机未测 |
| WP25-N-Android | **完成（自动化）** | Android 本地通知落地接线（接入 `flutter_local_notifications`、Android 清单权限与开机广播配置、模型扩展 `reminderAt`/`reminderTimezone`、WP11 数据迁移、31 位 FNV-1a 稳定哈希、新建与详情面板提醒时间选择器、设置页保活指南与权限检测）；`flutter test --no-pub` 237/237，`analyze --no-pub` 0 issues；实机未测 |
| WP25-N-Windows | **完成（自动化）** | Windows 桌面端本地通知适配与托盘联动（WinRT Toast 通知接入、托盘最小化保活定时提醒、点击通知唤醒窗口与深层路由、设置页 Windows 通知可靠性指南与测试通知按钮）；`flutter test --no-pub` 245/245，`analyze --no-pub` 0 issues；实机未测 |
| WP27-B-N | **完成（自动化）** | 完成历史与时间戳（Task/SubTask 扩展可选 completedAt 毫秒时间戳、勾选完成与取消撤销联动记录、7 日完成统计直方图、按完成时间降序排列、WP11 v2 序列化与 v1 降级剥离）；`flutter test --no-pub` 250/250，`analyze --no-pub` 0 issues；实机未测 |
| WP09-N | **完成（自动化）** | 首次引导教程与手势说明（5 页响应式引导页滑动浏览、跳过与首启自动弹出、本地已阅标记持久化与重置测试、设置页随时重新打开教程、三语完整本地化）；`flutter test --no-pub` 255/255，`analyze --no-pub` 0 issues；实机未测 |
| 其他未完成包的 Flutter / 研究 / 发行 / 服务子批次 | 待实施 | 下一包可领取 WP10-N（多选批量拖动移动）或进入 V1.0 发行准备（WP28-R）；已有能力只回归 |
| 其余未实施 React W 子批次 | 取消 | 不删除需求，将客户端实施保留在对应 Flutter 包 |
| UI 实验版 | 待基础验收后领取 | 见第 10 节；尚未建分支 |

旧 fork/商业方向暂停原因已解除；MF21/MF23 等已有能力只回归，MF28 并入 MF10。不把规划当作修复，不把取消当完成，也不把发布/托管服务写成已上线。

## 10. 基础完成后的 UI 实验版（未来独立小包）

**启动条件：** WP20-N、WP21-N、WP03-N、WP04-N、WP23-N、WP12-S-N、WP22-A/B-N 已完成，并有 Android/Windows 基础交互记录。缺设备时记录缺项，不伪造已验收；不要求等 Planner/同步/托管服务。当前 WP21-N 助手不得创建分支或顺带试画 UI。

1. **固定共同基线。** 从同一经过检查的提交创建用户指定的 `UI实验版` 分支，使用合成多板任务和独立测试数据；保留主线原版作对照。首批落点 `matrixflow-native/lib/theme.dart` 和小型可复用表面/按钮组件，沿用同一模型、Store、命令和交互。Flutter 可实现亮暗双阴影、渐变、内凹绘制与动效；先试轻拟态工具栏/输入区/按钮，不恢复层层大框，不改变 WP20 的完成/多选含义。
2. **按同一场景比较。** Android 360–412 dp、Windows 窄/宽窗、浅深色/大字体；相同数据完成添加、勾选、子项展开、编辑、搜索、聚焦、长列表滚动，比较正文可见量、误触、操作步骤及 profile 帧耗时。先只变视觉，后续要变密度/控件位置时单独记录变量；核心回归和平台检查仍适用，不以截图漂亮替代交互验证。可由用户本人比较，无需几十人试用。
3. **收敛到一条主线。** 交付前后截图、体验/性能记录与采用建议，将选定方案合回 main；如保留两种皮肤，用同一程序主题选项共享业务，避免两个长期分叉版本。UI 实验不牵涉 React 重启、数据迁移或收费服务，不把“平面化”写成 Flutter 的能力上限。
