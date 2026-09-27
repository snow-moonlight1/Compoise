# 开发指南

方寸 · Compoise 的持续开发版本是仓库根目录的 Flutter 应用。`legacy/web/` 中的 React、Tauri 和 Capacitor 原型已冻结，仅供历史参考。

## 环境要求

- Flutter 3.32.8 stable（Dart 3.8.1）
- Android：Android SDK、JDK
- Windows：Windows 主机和 Visual Studio 的“使用 C++ 的桌面开发”工作负载

Flutter 版本记录在 `.flutter-version` 与 `toolchain.json`。可使用版本管理器安装 SDK，并确保 `flutter`、`dart` 命令可从终端调用。

## 获取依赖、检查与运行

在仓库根目录执行：

```sh
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
flutter devices
flutter run -d <device-id>
```

Windows 桌面调试：

```sh
flutter config --enable-windows-desktop
flutter run -d windows
```

## 图标与构建

应用图标源文件位于 `assets/branding/CompoiseLogo.png`。更新图标资源后运行：

```powershell
powershell -ExecutionPolicy Bypass -File tool/generate_brand_icons.ps1
```

构建体验包：

```sh
flutter build apk --release --no-tree-shake-icons
flutter build windows --release
```

Android 正式发行需要发布签名。`android/key.properties.example` 是无密钥模板；复制并填入本机签名信息后保存为 `android/key.properties`，或使用发行脚本支持的环境变量。实际 keystore 和口令不得提交。Windows 当前构建不提供 Authenticode 签名。仓库自带的发行脚本会检查版本、签名和产物清单：

```powershell
powershell -File scripts/build_release.ps1 -ValidateOnly -ExpectedTag v1.0.0+1
```

## 数据与隐私边界

普通任务数据保存在本机。AI 密钥保存在系统安全凭据存储；用户主动调用 AI 时，相关任务文本会发送到其设置的模型端点。默认 JSON 备份不含密钥；显式选择加入时，备份内的密钥是明文。请勿提交真实任务备份、API 密钥、签名材料、日志或本机配置。

按任务查找其他说明见 [文档导航](README.md)。
