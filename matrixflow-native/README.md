# MatrixFlow AI Flutter 客户端

`matrixflow-native/` 是当前继续开发的 Android 与 Windows 客户端。Flutter 直接绘制界面，不经过 WebView。两端共用 `lib/` 里的任务、存储和 AI 代码；触摸与鼠标、键盘、窗口的差异留在各自工程和适配层。

仓库没有 remote。这里的本地构建不是已发布的测试版，也不是稳定发行。状态说明、数据边界和发行门槛见仓库根目录 [README.md](../README.md)。

## 目录

```
lib/main.dart                 入口
lib/models.dart               任务、看板、设置、AI 配置与 ExportData
lib/storage.dart              Store、SharedPreferences 与导入导出
lib/save_protocol.dart        本机双槽保存
lib/credential_store.dart     API 密钥的系统凭据
lib/ai_service.dart           三协议请求与模型发现
lib/ai_presets.dart           DeepSeek、火山引擎、百炼与自定义端点
lib/data_migrations.dart      v1/v2 读取
lib/l10n.dart                 en / zh / ja
lib/screens/                  矩阵、设置、搜索、完成、引导、启动恢复
lib/services/                 提醒、Windows 托盘与单实例
lib/widgets/                  任务卡片、象限、列表与详情
android/                      Android 工程
windows/                      Windows 工程
test/                         默认 dart 测试
integration_test/app_test.dart  带 mock 的集成入口
toolchain.json                固定的 Flutter 3.32.8 声明
```

根目录的 React、Tauri、Capacitor 不在这个目录里，已经冻结。

## 命令

工作目录是 `matrixflow-native/`。使用固定 SDK，不要改回退安装 `D:\Dev_SDKs\Flutter_SDK`。

```powershell
& "D:\Dev_SDKs\Flutter_3.32.8\bin\flutter.bat" pub get
& "D:\Dev_SDKs\Flutter_3.32.8\bin\flutter.bat" analyze --no-pub
& "D:\Dev_SDKs\Flutter_3.32.8\bin\flutter.bat" test --no-pub
& "D:\Dev_SDKs\Flutter_3.32.8\bin\flutter.bat" test --no-pub integration_test/app_test.dart
& "D:\Dev_SDKs\Flutter_3.32.8\bin\flutter.bat" build apk --debug
& "D:\Dev_SDKs\Flutter_3.32.8\bin\flutter.bat" build windows --debug
& "D:\Dev_SDKs\Flutter_3.32.8\bin\flutter.bat" run -d windows
```

`integration_test/app_test.dart` 走生产入口和 HTTP mock。它不代替真机触摸、软键盘、焦点或通知点击验收。

调试 APK 用 `build apk --debug`。没有正式证书时，`build apk --release` 仍可能得到 debug 签名包。正式归档在仓库根目录执行 `scripts\build_release.ps1`。当前缺少 `android/key.properties` 时，Android 正式打包会被拒绝；Windows 绿色包保持未签名。步骤、JDK 与 Visual Studio 要求见 [开发指南](../docs/DEVELOPMENT.md)。

默认测试和分析的最近一次集成记录写在 [HANDOFF](../docs/HANDOFF.md) 顶部。数字以当次命令输出为准。

## 行为入口

本地任务键、系统凭据、明文备份选项，以及 v1/v2 的有损边界，写在 [架构](../docs/ARCHITECTURE.md) 和 [备份格式](../docs/BACKUP_FORMAT.md)。AI 预设地址写在 [AI 预设](../docs/AI_PROVIDER_PRESETS.md)。
