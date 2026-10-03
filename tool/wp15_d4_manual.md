# WP15-D4 专用 VM 人工复现（未执行）

仅使用专用 Windows VM 的新用户配置文件，确认本次拥有该 VM/设备会话。正常程序读取该配置文件的库，不在当前宿主或已有用户库执行这些步骤。Android 要先确认 A1 已释放设备。物理输入、Narrator、全局 DPI/字号/时区仍需人工验收。

在本包工作树内，使用固定 SDK 生成纯合成 v3 数据（无模型下载、无应用启动）：

```powershell
$env:PUB_CACHE = "$PWD/build/wp15-d4/.pub-cache"
D:/Dev_SDKs/Flutter_3.32.8/bin/flutter.bat pub get --enforce-lockfile
D:/Dev_SDKs/Flutter_3.32.8/bin/dart.bat run tool/wp15_d4_fixture.dart
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tool/wp15_d4_checks.ps1 -Stage build
```

1. 在专用 VM 新配置文件中打开普通 `build/windows/x64/runner/Debug/compoise.exe`。设置 → Import JSON，导入 `build/wp15-d4/manual/spring.json`，审阅后确认。日程 → 切换显示时区为 `America/New_York`；选 2026-03-08。
2. 仅用实体 Tab/ShiftTab 到达重叠块和事件，Enter 各自打开；Escape 返回同一记录。编辑事件标题；Escape 显示放弃确认；默认 Enter 保留草稿，第二次 Escape 后选择放弃，库内容不变。编辑 → 确认页，先选择保留重叠，再 Enter 保存；重新打开检查标题。删除分别取消和确认，确认后焦点回到“添加日程记录”。
3. 周视图前后翻页各一次，回到今天，选日期；Tab 到周内各重叠记录时，应横向、纵向滚动到可见区域。午夜结束项只在 03-07，跨午夜项在 03-08/09；03-08 显示 23 小时。创建 03-08 02:30 应拒绝，不能自动顺延。
4. 导入 `fold.json`，选 2026-11-01：25 小时、01:00 的 -04:00/-05:00 两个位置。编辑重复时刻，修改时间后必须显式选偏移；保存后关闭程序并重新启动，重新打开仍为所选分支。关闭表单后切换显示时区，再打开编辑器，原记录时区和已选候选保持。
5. 明/暗主题分别测 320、390 logical px 和 2x、3x 字号。记录实际客户区物理像素、DPR、Windows DPI 和系统字号；应用内 TextScaler 注入不能替代此项。按按钮与输入框实际矩形检查可见性，取消/确认/偏移选择须可到达。
6. 开启 VM 的 Narrator，用读屏逐项进入：名称应区分时间块/事件、板、关联任务完成状态、两端日期/UTC 偏移和跨日延续。独立事件不能被读为可完成任务；每个重叠项应有单独动作。确认页的重叠勾选、保存、错误提示和放弃对话框均应可读；记录实际播报及键盘操作。
7. 仅在该专用 VM 中记录原系统时区，选择“使用设备时区”，开放日程及 fold 草稿后改变系统时区再恢复；表单的原记录时区/输入/偏移不变。关闭/重新进入、真实前后台恢复各测一次。比较导出：忽略 timestamp 后，日程 startAt/endAt/timeZoneId 与父任务 plannedDate/deadline/reminderAt/象限不变。

证据写入 `build/wp15-d4/manual/`：VM 身份、会话所有权、程序/源码 SHA、系统设置、实际操作、原始结果、退出码、PNG/播报记录、恢复前后时区及未完成项。以上步骤是未验复现说明，不是通过证据。
