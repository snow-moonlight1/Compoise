# OS27 文档子批次记录

本文件记录 A 分支提交时的状态；三批合并后的最终状态以 [HANDOFF 顶部](HANDOFF.md) 为准。

日期：2026-09-25。子批次：公开文档（HANDOFF 里的 A）。基线 `1625c1767b1893847ff4650218aba0e41a2886d4`。

## 工作区

- 动手前 `main` 就是这个提交，工作区干净。`git worktree list` 与 `git branch` 里没有 `os27` 名称，`D:\Dev_project\martix-wt-os27`、`martix-wt-os27-docs`、`martix-wt-os27a` 三个目录都不存在。
- 新建 worktree：`D:\Dev_project\martix-wt-os27-docs`，分支 `os27-docs`，HEAD 与基线相同。
- 没有 reset，没有 amend，没有 push。主工作区留在 `main` 的该提交。
- 本子批次不改 `l10n.dart`、引导页、托盘文案、平台验收记录，也不改 `AGENTS.md`、`HANDOFF.md`、`CHANGELOG.md` 和两份实施计划。

## 改了什么

| 文件 | 改动 |
|---|---|
| `README.md` | 去掉 328 项徽章、绝对隐私、绝无代理和跨端无损承诺。写明三种对外状态、本机任务、AI 发送内容和 v1/v2 边界。 |
| `matrixflow-native/README.md` | 去掉按文件拆开的过期测试计数，改成当前目录和固定 SDK 命令。 |
| `matrixflow-native/pubspec.yaml` | 只改 `description`。版本仍是 `1.0.0+1`。 |
| `docs/ARCHITECTURE.md` | 增加当前数据、AI 与发行状态。把后半部 Web/v1 地图标成冻结快照，并改掉「备份仍总是带密钥」「当前版本是 1」这类句子。 |
| `docs/DEVELOPMENT.md` | 去掉「下一包 WP03-N」。命令改成固定 `flutter.bat`、调试构建和发行脚本。冻结 Web 的 `npm run tauri build` 改为说明当前 `package.json` 没有这个脚本。 |
| `docs/README.md` | 新的文档索引。标出仍含未配置 GitHub 地址或「已经首发」的旧文。 |
| `CONTRIBUTING.md` | 新文件。参与方式与本地提交风格；Issue / Pull Request 地址待配置。 |
| `SECURITY.md` | 新文件。安全联系方式待配置；写明系统凭据、明文备份和可配置端点。 |
| `docs/OS27_DOCS_NOTES.md` | 本文件。 |

Material Icons 的署名加在根 README。固定 SDK 的 `D:\Dev_SDKs\Flutter_3.32.8\bin\cache\artifacts\material_fonts\materialicons_license.txt` 开头是 “Attribution 4.0 International”。该文件正文没有单独的 “Google” 署名行，所以 README 只写字体名称和 CC BY 4.0，并链接到 <https://creativecommons.org/licenses/by/4.0/>。应用内关于页属于文案子批次，本包没改。本基线上的 `docs/RELEASE_PLAN.md` 表格已经把该字体写成 CC-BY 4.0，本包没有再改那份计划。

## 核对过的命令和链接

2026-09-25 在本 worktree 执行：

```powershell
powershell -File scripts\build_release.ps1 -ValidateOnly -ExpectedTag v1.0.0+1
```

退出码 0。输出摘要：Flutter 3.32.8，revision `edada7c56edf4a183c1735310e123c7f923584f1`，engine `ef0cd000916d64fa0c5d09cc809fa7ad244a5767`，Dart 3.8.1，与 `toolchain.json` 一致。签名来源是 missing。Android 正式产物名将是 `matrixflow-v1.0.0+1-android.apk`，但真正构建会被拒绝。Windows 产物名将是 `matrixflow-v1.0.0+1-windows-portable.zip`，Authenticode 未配置。脚本声明没有写文件。

另外对照过这些路径，没有把它们重新执行一遍：

- `D:\Dev_SDKs\Flutter_3.32.8\bin\flutter.bat` 存在。
- `.github/workflows/pr.yml` 含有 `flutter analyze --no-pub`、`flutter test --no-pub`、`flutter build apk --debug`、`flutter test --no-pub integration_test/app_test.dart`、`flutter build windows --debug`。
- 根 `package.json` 的 scripts 只有 `dev`、`build`、`preview`。
- `vite.config.ts` 的端口是 3000。
- 根目录 `android\gradlew.bat` 存在。`matrixflow-native\android\gradlew.bat` 不存在，所以开发指南不把后者写成日常入口。
- `git remote` 为空，`git tag` 为空。

相对链接：对本包改过的 7 个 Markdown 文件解析了 85 条本地链接，0 条缺失。外链只保留 Creative Commons 的许可文本，没有填写组织仓库地址。

默认测试 560/560 和分析 0 issues 来自这个基线的 HANDOFF 顶部，是当时的集成记录。本子批次没有重跑 `flutter test`、`flutter analyze` 或双端构建。

## 待补

文案子批次（B）尚未并入。引导页和托盘里未本地化的句子、三语占位符，以及应用内 Material Icons 署名，都还没在本包处理。

平台证据子批次（C）尚未并入。本包没有 Android 设备操作、Windows 焦点与窗口、托管 runner，也没有把 `-Platform Windows` 真正打出来。文档里的调试构建命令与 workflow 文本一致，但不等于本机刚刚构建成功。

集成人还需要收口，本包故意没改：

- `AGENTS.md` 仍把文档索引指到根 README，文首进度也还是集成前的句子。
- `docs/HANDOFF.md`、`docs/CHANGELOG.md` 和开源准备计划里的 OS27 状态仍待集成人改成这一批完成后的事实。
- `docs/PRIVACY_POLICY.md` 仍写密钥明文在 SharedPreferences、备份总是包含密钥，并链接 `https://github.com/matrixflow/matrixflow`。本仓库没有这个 remote。
- `docs/STORE_LISTING.md` 使用同一个未配置地址，并保留绝对隐私文案。没有商店上架记录。
- `docs/release_notes/v1.0.0.md` 标题是已经首发，正文还有已删除的命令台、绝对隐私，以及 `git clone https://github.com/matrixflow/matrixflow.git`。
- `docs/RELEASE_PLAN.md` 第 3 节流程图仍画着缺少证书时回退 debug 签名。脚本的正式 Android 路径会拒绝。同文后部仍有「绝对隐私」句子。
- `docs/DATA_COMPATIBILITY.md` 的 v1 行写「清洗去重」。迁移器对重复板/任务 ID 仍保留首条；设置页导入另有 OS07 预检。细节以 `docs/BACKUP_FORMAT.md` 页首为准。
- `docs/CHANGELOG.md` 历史条目里的 `npm run tauri build` 保持原样，不改写历史。

WP10、WP29 和界面实验继续暂停。React、Tauri、Capacitor 继续冻结。稳定发行仍然没有开始。

## 链接复查

提交前在 `D:\Dev_project\martix-wt-os27-docs` 复跑了 `-ValidateOnly`，退出码 0，签名材料仍是 missing，脚本没有写文件。同一目录下 7 个 Markdown 的 85 条本地链接全部指向现存路径。
