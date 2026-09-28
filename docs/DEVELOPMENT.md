# 开发指南

方寸 · Compoise 的持续开发版本是仓库根目录的 Flutter 应用。`legacy/web/` 中的 React、Tauri 和 Capacitor 原型已冻结，仅供历史参考。

## 环境要求

- Flutter 3.32.8 stable（Dart 3.8.1）
- Android：Android SDK、JDK
- Windows：Windows 主机和 Visual Studio 的“使用 C++ 的桌面开发”工作负载
- Linux：clang、CMake、Ninja、pkg-config、GTK 3、libsecret 与 Ayatana AppIndicator 开发包；图形桌面或 WSLg

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

Linux 桌面预览版（在 Ubuntu 24.04 / WSL2 + WSLg 验证）：

```sh
sudo apt-get update
sudo apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev libstdc++-12-dev libsecret-1-dev libayatana-appindicator3-dev
flutter config --enable-linux-desktop
flutter pub get
flutter run -d linux
flutter build linux --release
```

WSL 中须安装 Linux 版 Flutter SDK，并从 WSL 终端运行上述命令。若所在网络无法访问 pub.dev，可按 [Flutter 官方镜像说明](https://docs.flutter.dev/community/china)配置 `PUB_HOSTED_URL` 和 `FLUTTER_STORAGE_BASE_URL`。AI 密钥使用 Linux Secret Service（如 GNOME Keyring）；需要运行且解锁可持久保存的默认密钥环。新建 WSL 用户可能尚未配置默认密钥环，此时普通任务可用，但密钥保存会失败或等待密钥环响应。Linux 尚无系统提醒通知、托盘、全局快捷键和关闭到托盘；桌面设置中的 Windows 专属控件在 Linux 隐藏。

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
