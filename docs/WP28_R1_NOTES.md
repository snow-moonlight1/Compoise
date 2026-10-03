# WP28-R1：候选产物校验与本地 / CI 一致性

基线 `5fb4592ccc10cdcc1698e27f68d2367a3d83cf18`；独立分支 `codex/wp28-r1`，工作树 `D:/Dev_project/martix-wp28-r1`。固定 Flutter 3.32.8 / Dart 3.8.1，版本保持 `1.0.0+1`，未创建 tag。

## 实际修复

- `scripts/release_candidate.py` 是本地与 release CI 共用的标准库校验入口（Python 3.9+）。`proof` 绑定平台二进制的名称、大小、SHA-256、tag、完整 commit、实际工具链、源码差异指纹和身份 / 签名证据；Windows 还记录 ZIP 每个文件的哈希，并证明 ZIP 完整覆盖构建目录。
- `RELEASE_MANIFEST.txt` 改为内部 JSON schema 1；`RELEASE_METADATA.txt` 从同一记录生成，直接包含证书 DN / SHA-256、Windows 身份、签名事实及源码状态。两者披露无 OCR、Linux preview、GPL-3.0-only、备份 v3 与本机凭据升级提示。每个阶段用同一套规则验证，SHA256SUMS 覆盖二进制、证明、manifest、metadata，以及存在时的 release notes。
- 校验采用精确版本 / 平台集合，拒绝缺失、旧版本、额外文件 / 目录、陈旧证明、错误 commit / pin、摘要缺失 / 重复 / 篡改。`seal` / `proof` 失败使旧成功记录失效；正式双平台装配还拒绝未提交源码差异。构建前后检查源码指纹和 HEAD，防止混入构建期间的修改。
- Android 本地脚本与 CI 共用真实 `apksigner verify --print-certs`、固定证书 SHA-256 和 `aapt2 dump badging` 门禁；工具缺失、执行失败、缺证书、debug 证书、错 pin / 包名 / 版本直接阻断，取消原本“未验证但继续暂存”的分支。未创建或读取生产 keystore，未更改用户签名配置。
- Windows 保持 `NotSigned` 便携包契约。拒绝启用 OCR / U2 诊断构建环境门及 ZIP 中 OCR runtime、模型、字典 / model card、额外许可成品；逐文件校验完整包。未修改 OCR 构建、模型锁或 runner。
- `workflow_dispatch` 仅运行预检 / 可执行回归和 Windows 候选构建上传，无生产签名 secrets；Android / Linux 正式门及 draft Release 仅 tag push 触发。工作流仍默认 `contents: read`，只有原 publish job 有 `contents: write`。

## 验证与证据

证据根：`D:/Dev_project/martix-wp28-r1/release_dist/wp28-r1-evidence`（忽略且不提交）。

| 实际命令 / 检查 | 退出码 / 结果 |
| --- | --- |
| 固定 SDK `flutter pub get` | 0，未更新 lockfile |
| `flutter analyze --no-pub` | 修复测试字符串转义后 0，无问题 |
| `flutter test --no-pub test/os26_release_test.dart` | 修复后 0，12 项通过 |
| `python -m unittest discover -s scripts/tests -p test_release_candidate.py -v` | 0，23 项真实 CLI 测试，含正反例与合成双平台装配 |
| YAML 解析、Bash `-n`、PowerShell AST | 0；15 个 Bash 块、9 个 PowerShell 脚本 / 块通过；dispatch / 发布权限条件检查通过 |
| `build_release.ps1 -Platform All -FlutterSdk D:/Dev_SDKs/Flutter_3.32.8 -ExpectedTag v1.0.0+1 -ValidateOnly` | 0，pin matches；不写产物 |
| 同一预检使用 `-ExpectedTag v9.0.0+1` | 1，预期拒绝 |
| `build_release.ps1 -Platform Android -OutputDir release_dist/android-blocked -FlutterSdk D:/Dev_SDKs/Flutter_3.32.8 -ExpectedTag v1.0.0+1` | 1，缺正式签名，未产出成功 manifest / 正式 APK |
| 首次 Windows Release 构建、身份校验、打包、seal / verify | 0；构建 143.2 s；ZIP 13,992,280 字节；未启动应用 |

首次预验证 ZIP 位于 `release_dist/round1/compoise-v1.0.0+1/`，证明如实记录基线 commit 和未提交源码指纹。最终候选须在本包提交后从该完整 commit 重新构建，最终交接附两轮候选 manifest / SHA 与证据；不能把预验证产物当作干净 commit 候选。

```powershell
# 在本包最终提交的工作树执行；两轮使用独立输出目录。
pwsh -NoProfile -File scripts/build_release.ps1 -Platform Windows -OutputDir release_dist/final-round1 -FlutterSdk D:/Dev_SDKs/Flutter_3.32.8 -ExpectedTag v1.0.0+1
pwsh -NoProfile -File scripts/build_release.ps1 -Platform Windows -OutputDir release_dist/final-round2 -FlutterSdk D:/Dev_SDKs/Flutter_3.32.8 -ExpectedTag v1.0.0+1
$commit = (git rev-parse HEAD).Trim()
python scripts/release_candidate.py verify --directory release_dist/final-round2/compoise-v1.0.0+1 --platform Windows --tag v1.0.0+1 --commit $commit
python scripts/release_candidate.py extract --directory release_dist/final-round2/compoise-v1.0.0+1 --platform Windows --tag v1.0.0+1 --commit $commit --output release_dist/final-extracted
```

重复归档哈希相同只证明本次同一缓存构建目录的归档可复现；逐文件比对可报告两次增量构建的字节一致性，不代表清理缓存后的 Flutter 独立全量构建可复现。

## 尚未验收

生产 Android 签名与正式渠道材料缺失，正式 APK 继续阻断。合成 APK / 证书证明只验证拒绝与装配规则，不能视为真实签名或设备验收。证明是受控构建步骤的哈希追踪记录，不是独立的密码学构建证明。

GitHub 云端 workflow 未运行；这里只进行了本地语法与等价 CLI 回归，待集成端 push 验证。未启动 Windows 应用、未使用 Android / Linux 设备；正式版本原位升级、发布版本 / tag / 渠道批准、签名和设备门仍由集成端验收。不改 main、不 push、不发布、不再派 Agent。
