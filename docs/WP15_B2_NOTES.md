# WP15-B2：备份日程预览与兼容提示验收

日期：2026-10-01（Asia/Shanghai）。在已附着的独立工作树 `C:/Users/20214/.codex/worktrees/wp15-b1-backup-v3/martix` 中，从集成基线 `ea6c4d0d8e58dd15e4c68d9824c9c0ac0bb445c6` 新建 `codex/wp15-b2`；保留原 B1 分支。依据 [WP15 契约第 5 节](WP15_CONTRACT.md)、[B1 验收记录](WP15_B1_NOTES.md) 和 [备份格式](BACKUP_FORMAT.md)。本包独立提交，不推送。

## 实现范围

- 设置页备份区域、导出凭据选择框和导入模式选择框显示 en/zh/ja 版本说明：默认完整 v3 包含日程，继续接受 v1/v2/v3；旧版应用不能读取 v3，旧格式不能恢复日程。
- 导入确认直接使用 B1 的 `ImportPlan` 计数，分别展示日程新增、相同内容跳过、ID 冲突、覆盖删除数量。任务新增为零时，日程冲突仍单独解释并禁用确认；不改变核心冲突规则。
- 缺省版本、v1、v2 覆盖时，在确认之前明确展示现有日程删除数量。旧格式夹带 `scheduleItems` 时，始终单独说明忽略该字段，成功消息也明确没有恢复任何日程。即使其他预检警告超过八条，此说明仍保留。旧格式合并保留本机日程。
- 默认导出仍只调用 `Store.exportBackup(includeCredential: ...)`。当前界面没有旧格式导出入口，本包不新增版本菜单，也不传 `allowScheduleLoss: true`。保留数据层拒绝门禁；若出现 `ScheduleExportLossException`，转换为含丢失数量的三语失败提示，不写文件、不重试降级。
- 新增专用备份消息适配文件，将版本错误、日程合法性错误和未知字段/归一化警告转换为本地化类别。警告详情去重并限制八类，计数继续显示原始预检结果；不回显异常文本、未知字段名、备份记录或 API 密钥。通用格式、容量和保存失败继续沿用既有消息。
- 导出警告同步覆盖日程及关联记录组上限；导入覆盖和目标板说明包含日程/独立事件。取消、写失败、忙碌时重复进入及宿主卸载仍使用原生命周期机制。

修改仅涉及 `lib/screens/settings_backup_flow.dart`、`lib/screens/settings_backup_messages.dart`、`lib/screens/settings_screen.dart`、`lib/l10n.dart` 的三语既有备份区域、`test/wp15_b2_backup_flow_test.dart` 和本记录。新增翻译键均以 `backup`、`export` 或 `importSchedule` 开头。未改 `schedule*` 前部翻译、OCR 评审翻译、Store、模型、迁移/预检、Planner、Android、导航或路线图；没有需要越界修改的数据层阻塞。

## 自动化证据

环境：Windows；Flutter 3.32.8 / Dart 3.8.1，SDK `D:/Dev_SDKs/Flutter_3.32.8`。全部数据和凭据为合成值。

新增 34 项测试，包含三语 v3 完整导出、360×640 的日程计数预览、任务零新增而日程冲突阻止确认、v3 合并实际恢复日程、旧格式合并保持日程、缺省/v1/v2 覆盖警告及忽略字段、超过八条警告时的兼容说明、未知字段名/值和错误信息的隐私检查。损坏用例包含未来/非法版本、缺数组、重复 ID、悬空任务/板、坏时区及非正时长。另验证取消选择、导出写失败、重复进入、卸载后文件选择返回，以及提交指针写失败时的英文界面结果和日程回滚。

有效命令与结果（`flutter` 指上述固定 SDK）：

```text
flutter test --no-pub test/wp15_b2_backup_flow_test.dart --reporter expanded
# 34 passed; exit 0

flutter test --no-pub test/wp15_b2_backup_flow_test.dart test/widget_regression_test.dart test/rf11_import_target_test.dart test/rf04_backup_contract_test.dart test/os08_os09_credential_test.dart --reporter expanded
# 155 passed; exit 0（包含新增测试）

flutter analyze --no-pub
# No issues found!; exit 0

git diff --check
# exit 0
```

第二个命令覆盖设置页实际按钮/凭据选择/刷新、目标板导入、分卷写入及失败/取消、完整恢复和凭据回归。已有 `widget_regression_test.dart` 的复选框点击命中警告和测试绑定 HTTP 提示仍为非致命输出，未修改其范围外用例。

开发阶段测试夹具的文件选择器初始化、定时器清理及合并模式确认按钮选择已修正；不修改生产生命周期或合并时不导入凭据的既有规则。为保持原设置页回归断言，导出版本说明和凭据警告分别使用文本节点。最终扩大旧版夹具至超过八条警告后，重新运行 34 项定向测试。

## 剩余门禁

- 按本包授权边界，没有再次运行全量 `flutter test` 或云端检查；由集成端在合入后执行。本包的 155 项结果不能替代最新集成基线的全量通过记录。
- 未做 Android、Windows、Linux 真机文件选择、写盘故障、跨平台多卷导入及屏幕阅读器验收；窄屏证据为 Flutter widget 测试。
- 旧可执行文件重写本地存储槽的兼容性和发行迁移提醒仍需集成/发布验收。新增界面说明不改变 B1 的数据版本和恢复能力。
- 若后续新增旧格式导出入口，仍须在调用前展示丢失数量并由调用方主动选择；本包的异常失败提示不是有损导出授权，也没有启用有损导出。

测试日志与 Flutter 自动生成文件不纳入提交；无推送、无 amend、无合并 main、无 B1 重复移植。
