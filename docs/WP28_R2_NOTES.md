# WP28-R2：隔离磁盘矩阵与同提交候选

基线：`3ac0b6d9192a0495f1db1f636d9b8726b03179c4`。独立分支
`codex/wp28-r2`，工作树 `C:/Users/20214/.codex/worktrees/wp28-r2/martix`。
固定 Flutter 3.32.8 / Dart 3.8.1，`pubspec.lock` 未变；独立
`PUB_CACHE=D:/Dev_project/martix-wp28-r2-cache`。没有修改主检出、推送、
amend、tag、Release、签名、版本、模型锁、Store、SaveProtocol 或备份 schema。

## 实现范围

- 合成库含三个板、父子/完成态、长纯文本备注及 plannedDate/deadline/reminder。
  v3 日程含独立/关联记录、跨日、纽约春季跳时/秋季重复时刻及重叠。
- 截图合成任务经过公开 `ImportSubmission` 和生产提交事务；故障注入失败时
  比较内存库与已提交槽，重试保留 ID，重复提交不复制，日期原文逐字比较。
  没有 OCR 调用、模型载入或截图设备验收。
- 真实 Windows Flutter/SharedPreferences 进程测试镜像、双槽、缺失旧日程、
  当前库优先、损坏槽/指针/日程/当前库、失败重试、未确认退出、竞争及双进程。
  升级来源文件逐字节比较，重开逐字段比较；v3/v1/v2 分别导入新 GUID 根并重开。
  v1/v2 导出先拒绝未确认的有损降级，再记录日程丢失数量和提示。
- 原生诊断入口在 COM/Flutter 前校验运行开关、严格 GUID、已存在的 OS-temp
  直接子目录及规范路径。私有 Win32 desktop 不切换输入桌面、不抢前台，
  每份报告校验根、namespace、PID、desktop 和前台归属。D3/U2 编译门互斥。
  强制清理/超时均失败，只清理本次精确 PID，不扫描历史未知进程。
- 取证脚本先读取升级文件摘要，再通过仅诊断入口可用的握手允许 Store 打开；
  ready 报告前确认首次保存成功，避免观察者与写入者争用文件。
- R1 脚本未改。新增审计调用 R1 校验，检查完整解包文件集合、摘要、版本、
  正常编译门关闭及 UTF-8/UTF-16 诊断标记残留，比较两次同提交候选。

## 证据归属与命令

全部原始日志、合成库、截图事务回执和二进制位于本树忽略目录，不提交。
最终 `build/wp28-r2/handoff.json` 在源码提交后生成，记录完整提交、实际命令、
退出码及最终报告路径。最终诊断 proof、矩阵报告和正常候选 proof 均记录其
完整提交及 R1 源码差异指纹；诊断 `normalCandidate=false`，正常候选另行记录。
保留的早期诊断报告属于基线加当时源码差异，不能替代最终提交的验收。

提交前已完成：analyze 无问题；定向 18 文件 270 项通过；默认全量
1411 项通过、10 项条件跳过；R1 Python 24 项、R2 Python 5 项通过，退出码均 0。
全量条件跳过不是设备证据。定向文件列表在 `build/wp28-r2/targeted-files.txt`。
提交前 Debug/Release 均完成 20 场景、73 进程矩阵；运行时十项门禁负例通过，
三项编译门负例各预期退出 1（门禁脚本整体 0）。最终提交再执行原生验收。

在本树设置独立 PUB_CACHE 后执行：

```powershell
& D:/Dev_SDKs/Flutter_3.32.8/bin/flutter.bat pub get --enforce-lockfile
& D:/Dev_SDKs/Flutter_3.32.8/bin/flutter.bat analyze
# 定向文件参数见 targeted-files.txt；默认全量：
& D:/Dev_SDKs/Flutter_3.32.8/bin/flutter.bat test --no-pub --reporter expanded
python -m unittest discover -s scripts/tests -p test_release_candidate.py
python -m unittest discover -s scripts/tests -p test_wp28_r2_candidate_audit.py
pwsh -NoProfile -File scripts/wp28_r2_windows_gates.ps1 -Run -Kind Build
pwsh -NoProfile -File scripts/wp28_r2_build_diagnostic.ps1 -Run -Configuration Debug
pwsh -NoProfile -File scripts/wp28_u2_windows_harness.ps1 -Run -Configuration Debug
# Runtime 的 MatrixReport 必须指向刚通过的对应矩阵；Release 重复上述三步。
pwsh -NoProfile -File scripts/wp28_r2_windows_gates.ps1 -Run -Kind Runtime -MatrixReport <harness.json>
```

最终诊断束复制到 `build/wp28-r2/diagnostic-bundles/Debug`、`Release`，
proof 保存为 `final-diagnostic-Debug.json`、`final-diagnostic-Release.json`；
逐文件核对后保留，正常构建可以覆盖 Flutter 的 runner 目录。

源码提交后关闭 U2/D3/OCR 编译门，以同一个完整 HEAD 两次执行：

```powershell
pwsh -NoProfile -File scripts/build_release.ps1 -Platform Windows -OutputDir release_dist/wp28-r2-round1 -FlutterSdk D:/Dev_SDKs/Flutter_3.32.8 -ExpectedTag v1.0.0+1
# round2 使用独立 OutputDir；R1 构建脚本执行 proof/seal/verify。
python scripts/release_candidate.py extract --directory <candidate> --platform Windows --tag v1.0.0+1 --commit <full-HEAD> --output <fresh-extracted-dir>
python scripts/wp28_r2_candidate_audit.py --first <round1-candidate> --second <round2-candidate> --extracted-first <round1-extracted> --extracted-second <round2-extracted> --commit <full-HEAD> --output build/wp28-r2/candidate-comparison.json
```

两次候选只代表本机增量构建比较，不扩大为独立干净缓存可重复构建证明。
候选 ZIP、完整逐文件摘要、源码指纹和实际比较结果以最终 proof/比较报告为准。
诊断与正常二进制不混作证据，正常候选不在宿主真实用户库启动。

## 修复前失败与限制

- 仅检查规范路径时，GUID 名称的普通文件误通过原生根门禁并进入引擎；
  六秒探针超时，精确清理自有 PID 4984。`file-root-before-fix.json` 记为失败。
  修复为原生文件句柄检查目录属性，Dart 同时要求目录实际存在；最终负例须在
  COM/引擎前退出 2、输出为空、根无写入。
- 三项编译负例后的 CMake 默认安装前缀缓存导致一次诊断构建失败，日志
  `debug-build-first.log`。脚本只隔离本树缓存，再重新配置；没有安装到 Program Files。
- 一轮 Debug 竞争场景出现 `Synthetic save incomplete`，该轮失败且清理自有
  PID 24428，报告 `Debug/1596ce3e-e8d0-42e8-9c26-c9e9dc4096c0/harness.json`。
  文件摘要读取与启动保存争用是诊断推断；新增握手明确时序，后续完整轮次通过。
  没有因此修改产品 Store/SaveProtocol，也不把失败轮次计为通过。
- Release 门禁脚本曾因优化后的 ASCII 方法名不再连续存于 EXE 而在预检拒绝，
  没有启动负例进程。改为检查两种配置都保留的原生宽字符串门禁，并仍绑定
  刚通过的矩阵、精确路径和 EXE 摘要，修复后十项负例通过。
- 没有可验证的隔离 VM/Windows Sandbox；**正常候选真实安装/升级未验**。
  没有新建账户、启用系统功能、修改宿主时区或在宿主真实用户库运行正常包。
  正式签名、渠道、最终发行版本和 WP28 总体验收仍未批准；本包不发布。
