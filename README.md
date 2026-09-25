# MatrixFlow AI

本地优先的艾森豪威尔矩阵待办。持续开发的客户端是 `matrixflow-native/` 里的 **Flutter Android 与 Windows**。任务存在本机。需要 AI 时，由你填写密钥，应用把当次请求发到你配置的端点。

MatrixFlow AI is a local-first Eisenhower-matrix task app. The maintained client is the Flutter Android and Windows app in `matrixflow-native/`. Tasks stay on the device. AI requests go to an endpoint you configure, with a key you provide.

根目录的 React、Tauri 与 Capacitor 工程冻结保留，只作历史参考。WP10、WP29 和界面实验继续暂停。

## 现在处于哪一步

OS01–OS27 已集成，2026-09-25 复审后的当前工作见[最后一轮返修计划](docs/IMPLEMENTATION_PLAN_2026-09-25_FINAL_REPAIR.md)和[逐包审查报告](docs/OS_IMPLEMENTATION_REVIEW_2026-09-25.md)。已复现的导入、凭据、备份与交互边界问题尚待修复，不能把集成完成视为稳定发行。

这三件事是分开的。本仓库目前只具备第一栏里的本地源码。

| 状态     | 现在的事实                                                                 |
| ------ | --------------------------------------------------------------------- |
| 源码     | 源码在本仓库，许可证是 [MIT](LICENSE)。`git remote` 为空，公开托管地址、问题跟踪和分支保护都还没配置。     |
| 测试版二进制 | 没有托管的测试下载页。本机可以打 Android debug APK，以及未签名的 Windows 调试或桌面构建。这些构建没有分发渠道。 |
| 稳定发行   | 尚未发行。没有正式 Android 签名证书、Windows 代码签名、git tag、Release，也没有覆盖安装保留数据的设备记录。 |

维护者邮箱和安全联系地址待配置。在持有人给出真实地址之前，本文不填写组织 URL 或邮箱。报告方式见 [SECURITY.md](SECURITY.md)，参与方式见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 数据留在哪里，AI 会发出什么

待办、看板、非敏感 AI 配置和应用设置写在本机 SharedPreferences。应用没有另做任务库加密，也没有账号或云同步。核心键是 `matrixflow-tasks`、`matrixflow-boards`、`matrixflow-config`、`matrixflow-settings`。

API 密钥走系统凭据（`flutter_secure_storage`）：Android 使用 Keystore 与 AES-GCM，Windows 使用凭据管理器保存密钥、应用目录保存密文。默认 JSON 备份省略 `customApiKey`。只有在设置里每次明确选择包含密钥时，应用才从系统凭据读出密钥，并在警告后把它写成明文 JSON。旧的带密钥 v1/v2 文件仍可读取。覆盖导入默认保留本机密钥。合并导入不带入配置和密钥。

AI 在你执行分类、分组或拆解时才发送网络请求。分类和分组发送的是这次输入的任务标题；拆解发送的是被选中的长期任务标题。请求去往你保存的地址：DeepSeek、火山引擎、阿里云百炼有预设 HTTPS 端点，自定义地址可以指向其他兼容服务、反代或 HTTP。应用自身不运营中转服务。模型发现只带密钥请求模型列表，不含任务正文。生成探测会先说明可能计费，确认后才发送一次很短的 `ping`。

备份默认是 ExportData **v2**。没有版本号的文件按 **v1** 读取。当前 Flutter 能读 v1 和 v2，并拒绝未知版本。v1 降级导出是有损的：会失去手动紧急模式、笔记、提醒、完成时间，以及一部分显示与桌面设置。冻结的 React 不保证能无损读回 v2。Android 与 Windows 使用同一份备份格式。这是手动文件交换，不是自动同步。字段与导入规则见 [备份格式](docs/BACKUP_FORMAT.md)。

## 构建与测试

固定 SDK 是 Flutter **3.32.8** stable / Dart **3.8.1**（framework `edada7c56edf4a183c1735310e123c7f923584f1`，engine `ef0cd000916d64fa0c5d09cc809fa7ad244a5767`）。本机目录是 `D:\Dev_SDKs\Flutter_3.32.8`。回退目录 `D:\Dev_SDKs\Flutter_SDK` 保持不动。机器可读声明在 [toolchain.json](matrixflow-native/toolchain.json)。

下面的 `flutter.bat` 就是这套固定 SDK。系统 PATH 里的其他 `flutter` 不作为本仓库的工具链。先进入 `matrixflow-native/`，再执行：

```powershell
Set-Location matrixflow-native
& "D:\Dev_SDKs\Flutter_3.32.8\bin\flutter.bat" pub get
& "D:\Dev_SDKs\Flutter_3.32.8\bin\flutter.bat" analyze --no-pub
& "D:\Dev_SDKs\Flutter_3.32.8\bin\flutter.bat" test --no-pub
& "D:\Dev_SDKs\Flutter_3.32.8\bin\flutter.bat" build apk --debug
& "D:\Dev_SDKs\Flutter_3.32.8\bin\flutter.bat" build windows --debug
```

新增依赖或锁文件无法解析时才需要 `pub get`。`build apk --debug` 是调试包。没有正式证书时，`build apk --release` 仍可能打出 debug 签名的 APK，不能当作稳定发行物。

正式归档回到仓库根目录执行。若上一段命令已经进入 `matrixflow-native/`，先执行 `Set-Location ..`。

```powershell
powershell -File scripts\build_release.ps1 -ValidateOnly -ExpectedTag v1.0.0+1
powershell -File scripts\build_release.ps1 -Platform Windows -ExpectedTag v1.0.0+1
```

当前 `pubspec.yaml` 版本是 `1.0.0+1`。`-ValidateOnly` 只核对版本和签名前提，不写产物。2026-09-25 在本基线上执行该命令的结果是：工具链与 `toolchain.json` 一致，Android 签名材料缺失，因此真正的 `-Platform Android` 或 `-Platform All` 会拒绝构建。Windows 归档名将是 `matrixflow-v1.0.0+1-windows-portable.zip`，且没有 Authenticode 签名。证书模板见 [key.properties.example](matrixflow-native/android/key.properties.example)。

基线 `1625c1767b1893847ff4650218aba0e41a2886d4` 的集成交接记录了默认测试 560/560、分析 0 issues。那是当时的本地记录。本文件不把它写成实时配额，仓库也没有挂接这些数字的远程检查。

Android 构建还需要本机 Android SDK 与 JDK，Windows 桌面构建需要 Visual Studio 的 C++ 桌面工作负载。路径和冻结旧版命令见 [开发指南](docs/DEVELOPMENT.md)。

## 文档

贡献者从 [文档索引](docs/README.md) 进入。结构说明见 [架构](docs/ARCHITECTURE.md)，当前交接见 [HANDOFF](docs/HANDOFF.md) 顶部。客户端目录说明见 [matrixflow-native/README.md](matrixflow-native/README.md)。

## 许可与图标字体

客户端源码、脚本、测试和文档使用 [MIT License](LICENSE)。

界面图标来自 Flutter 打包的 Material Icons 字体。固定 SDK 中的许可文件 `D:\Dev_SDKs\Flutter_3.32.8\bin\cache\artifacts\material_fonts\materialicons_license.txt` 是 Creative Commons Attribution 4.0。署名：Material Icons，许可为 [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)。