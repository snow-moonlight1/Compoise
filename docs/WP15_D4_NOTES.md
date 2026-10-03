# WP15-D4：日程键盘与语义收口

2026-10-03；工作树 `D:/Dev_project/martix-wp15-d4`；分支 `codex/wp15-d4`；固定基线 `459f9a28cefdcac9196825b2d4ac70250dbf3b8d`，没有改用后续 main。实现提交 `738183e9bda2573adc18f6ddcbe4584c4efbde1d`；验收文档另作提交，其完整 SHA 随最终交接给出。提交身份仅在本工作树为 `wp15-d4-agent`。

## 修复与边界

- 编辑器和删除确认页显式支持 Escape。编辑器的 Escape/系统返回在草稿变化或拖动预填方案尚未提交时，显示放弃确认；默认焦点为“继续编辑”，Enter/Escape 可保留草稿。既有显式“取消”仍直接取消并零写入。保存等待时不能退出；已经接受但持久化失败的变更沿用原有保留/重试语义。
- 确认页焦点到“保留重叠”勾选或无重叠时的保存按钮；回表单、保存失败后的重试均有明确焦点，并滚动到可见区域。阻止保存/过期/恢复状态下的表单键盘访问，补足仅 AbsorbPointer 的缺口。详情→编辑/删除结束后回到原重叠项；删除成功回到“添加日程记录”并滚动到该入口。
- 日程语义分别标注关联任务未完成/完成，两端带完整日期和 UTC 偏移，午夜结束不会只读成同一天的 00:00。独立事件不加任务完成状态；每个重叠项仍有独立按钮、焦点和语义动作。
- 产品改动仅 `lib/screens/planner_screen.dart`、`lib/planner/schedule_editor.dart` 与三个语言的一个日程专属 l10n 键。未修改日程模型、Store、SaveProtocol、备份、设备时区桥、Windows runner、主入口、OCR、依赖/版本锁、共享文档或 test/helpers.dart。没有子 Agent、跨会话消息、push/amend/tag/Release。

新增两个 D4 测试文件共 22 项：键盘 Tab/ShiftTab/Enter/Space/Escape、编辑/删除、未保存离开、保存等待/失败/重试、焦点恢复、四组窄屏周视图和八组明暗主题表单/关联选择/重叠确认矩阵；日期选择取消、日/周/今天/前后导航；23/25 小时日、跨日午夜和最后 1ms 项；合成手工资料经生产 v3 导入验证。C1/C2/D1 既有回归继续验证 DST 候选显式选择、显示时区重投影和任务字段零改写。

## 工具与隔离

固定 SDK `D:/Dev_SDKs/Flutter_3.32.8`，校验 toolchain.json 的 Flutter 3.32.8 / Dart 3.8.1 / framework 与 engine revision。所有缓存、日志、临时库和输出均在本包私有工作树；缓存最终为 `build/wp15-d4/.pub-cache`，临时根 `build/wp15-d4/tmp`。依赖先 `pub get --enforce-lockfile`，移动缓存后 `pub get --offline --enforce-lockfile`，均 exit 0，pubspec/lock 未改。

`tool/wp15_d4_checks.ps1` 记录精确实际命令/退出码；默认测试 concurrency=1。`tool/wp15_d4_native.ps1` 复用基线 D3 六场景及其原生双门、GUID/PID/路径、专用 desktop、驱动/实际进程退出和清理校验，输出改为本包私有根并加强完整 SDK 校验；没有修改 D3/native 协议或正式入口。原生构建与默认测试串行执行。`tool/wp15_d4_fixture.dart` 只生成合成 v3 文件；人工步骤见 `tool/wp15_d4_manual.md`，不会自行启动设备或程序。

## 命令与证据

证据根：`D:/Dev_project/martix-wp15-d4/build/wp15-d4/`，全部忽略、不提交。targeted/analyze 在实现提交前执行，revision=固定基线、dirty=true；后续全量/原生/普通构建执行实现提交。`source-manifest.json` 记录实现提交的文件 SHA-256；生成插件文件及验收文档导致的 dirty 不代表另有未提交产品更改。

| 实际命令（固定 SDK；工作树内） | 结果 | 证据 |
| --- | --- | --- |
| `flutter pub get --enforce-lockfile` / `--offline --enforce-lockfile` | 两次 exit 0 | pub-get.log / pub-get-hidden-cache.log |
| `tool/wp15_d4_checks.ps1 -Stage targeted` | 133 通过 / 2 默认设备入口跳过，exit 0 | targeted.log / targeted-result.json |
| `tool/wp15_d4_checks.ps1 -Stage analyze` → `flutter analyze --no-pub` | No issues found，exit 0 | analyze.log / analyze-result.json |
| `tool/wp15_d4_checks.ps1 -Stage full` → `flutter test --no-pub --concurrency=1 --reporter expanded` | 1435 通过 / 12 跳过，exit 0 | full.log / full-result.json |
| `tool/wp15_d4_native.ps1`（无 -Run） | blocked，exit 2，不启动程序 | native-disabled.log |
| `tool/wp15_d4_native.ps1 -Run`（MSBUILDDISABLENODEREUSE=1） | 六个业务场景；build/driver/native/script exit 均 0 | native/windows-result.json / native-run.log |
| `tool/wp15_d4_checks.ps1 -Stage build` → `flutter build windows --debug --no-pub -t lib/main.dart` | exit 0；普通目标、Dart/native D3/U2 门关闭，未启动 | build.log / build-result.json / normal-result.json |
| `dart run tool/wp15_d4_fixture.dart` | exit 0；两个生产导入验证通过 | fixture.log / manual/spring.json / manual/fold.json |

重跑：先设 `PUB_CACHE` 为上述本包隐藏缓存并 `pub get --enforce-lockfile`，然后逐个执行 targeted、analyze、full、native -Run、build。PowerShell 调用 `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tool/wp15_d4_checks.ps1 -Stage <阶段>`；native 使用同样调用格式。native 最后恢复普通构建，不启动普通程序/真实用户库。

原生复验自有 PID `46692`，命名空间 `fabcd451-513a-4c57-955e-8515a675ff2e`；没有 timeoutCleanup，nativeResidual/tempResidual 均 false，宿主时区前后均 `China Standard Time`。证据目录 `native/evidence/fabcd451-513a-4c57-955e-8515a675ff2e/` 包含 driver-result.json 与 planner-narrow-3x.png；截图为横向可滚动网格局部，不能当成整页全部文字已同时可见的证据。native-stdout.log 的 +8 包括 setUpAll/tearDownAll，实际业务场景为六个。仍有 integration_test 原生 plugin 未检测到的警告；本轮依据 VM driver 的标准结果、原生状态、真实 IO 与实际退出码，不称为 Windows instrumentation。

最终 native 状态 windowVisible/privateDesktop=true、foregroundOwned/queryInjected=false；20 次查询、各 2 次 settings/time 消息。实际凭据写入禁用、提醒为 in-memory。默认全量的 12 个跳过包含设备 opt-in 入口及当前卷不生成 8.3 路径的环境项，没有将其计入 1435 通过。生成插件源码在验收后恢复/移除；日志、PNG、合成库、二进制、缓存均不入提交。

诊断 exe SHA-256 `f0dd59ba996c8bcab1cc7ea2656d2ead8242d5b5ac08ca78c53a121ca6d99470`；kernel SHA-256 `dc7623414cd80aa7dc6df45edf809f0480a7e6d310477fa75707c9f7a842eb30`。

最后普通 Debug exe SHA-256 `79eb3c2b6aa08358bdc9f8f6a01bed49f73c474e529c45effe9084bb2b30b448`；锁文件 SHA-256 `93c91e4363a690e04b2e84613e7137bda02ecd18f493910bebbe816249a4b755`。normal-result.json 核对实际 main 目标与诊断门关闭；boundary-result.json 核对实现没有越界、source-manifest.json 的九个文件指纹均一致。

## 失败前后

- 初版 D4 基线测试 4 通过 / 4 失败，exit 1：三个实际缺口是草稿返回保护、编辑器 Escape、确认页焦点；第四个失败是测试少按一次菜单下箭头，修正为五次后再验证删除，不把该失败当产品缺陷。证据 baseline.log / baseline-result.json。
- 首轮定向 118 通过 / 1 失败 / 2 跳过，exit 1：删除后焦点落在其他项而非明确入口；改为成功删除后聚焦添加按钮并确保可见。证据 targeted-first.log；最终对应键盘测试通过。
- 首次 analyze 扫描可见包缓存，52446 项问题，exit 1；移入本包隐藏缓存并离线按锁重解析，无需改共享分析规则。第二次仅一个测试 for 语句 lint，exit 1，已补大括号。最终 exit 0。失败日志 analyze-visible-cache-failed.log / analyze-lint-failed.log。
- 收尾时包含循环清理的合并 shell 命令被自动策略拒绝，未执行、无进程退出码。拆为只读产物核对，再删除三个已确认归属本工作树的绝对文件路径，均 exit 0；没有请求或使用权限升级。

## 验证边界

widget/semantics 是 Flutter 自动化证据，不能当作真实读屏、物理输入、系统字号或高 DPI 验收。Windows 原生复验仍沿用 D3 的内部输入及显式时区查询/消息/恢复注入；不会据此声称真实全局时区切换、独立进程恢复或实体读屏通过。D4 的新增离开/重试焦点细节由 widget 测试覆盖，六个既有原生场景提供生产页面/磁盘回归。

未验：专用 VM 的 Narrator 实际播报、实体键盘/鼠标、Windows 全局 DPI/系统字号、真实系统时区及前后台恢复、Android/实体 Linux 的新增 D4 场景、Release/签名/安装/发布。已提供可生成合成库的精确人工复现步骤；本次未提供专用 VM 或实体设备会话的身份及串行所有权，未启动这些设备。未操作其他包 PID/目录、宿主时区、用户前台或真实用户资料。
