<p align="center">
  <img src="assets/branding/rounded_rectangle_logo.png" alt="方寸 · Compoise app icon" width="132" />
</p>

<h1 align="center">方寸 · Compoise</h1>

<p align="center"><strong>方寸之间，理清轻重缓急。</strong></p>

<p align="center">
  <a href="LICENSE"><img alt="License: GPL-3.0-only" src="https://img.shields.io/badge/License-GPL--3.0--only-3b82f6?style=for-the-badge" /></a>
  <img alt="Flutter" src="https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white" />
  <img alt="Dart" src="https://img.shields.io/badge/Dart-0175C2?style=for-the-badge&logo=dart&logoColor=white" />
  <img alt="Android" src="https://img.shields.io/badge/Android-3DDC84?style=for-the-badge&logo=android&logoColor=white" />
  <img alt="Windows" src="https://img.shields.io/badge/Windows-0078D6?style=for-the-badge&logo=windows&logoColor=white" />
</p>

方寸（Compoise）是一款面向 Android 和 Windows 的本地优先任务管理应用。它以艾森豪威尔四象限为核心，帮助你理清任务优先级、专注处理眼前事项，并在需要时使用 AI 整理和拆解任务。

*Compoise is a local-first task manager for Android and Windows. Organize work with an Eisenhower matrix, focus on one quadrant, and optionally use your own AI provider to classify, group, and break down tasks.*

## 功能

| 功能           | 说明                                          |
| ------------ | ------------------------------------------- |
| 四象限与聚焦       | 按重要性和紧急性整理任务，在总览与单象限聚焦之间切换。                 |
| 多任务板         | 将工作、学习和个人计划分开放置。                            |
| 父任务与子项       | 拆分较大的任务，并为任务添加笔记、截止日期和提醒。                   |
| 动态紧急性        | 根据截止日期和用户设置的阈值调整紧急状态；无需 AI。                 |
| AI 整理        | 对任务进行分类、分组，或将长期目标拆解为子项。                     |
| 查找与回顾        | 搜索任务和笔记、筛选任务并查看已完成事项。                       |
| 多语言与显示       | 支持简体中文、English、日本語，以及主题、字体大小和减少动画等设置。       |
| Windows 桌面操作 | 支持键盘操作、系统托盘和全局快捷键。                          |
| 手动备份         | 通过 JSON 文件导入和导出数据，在 Android 与 Windows 之间转移。 |

Android 桌面图标下方的应用名会按系统语言显示为「方寸」或「Compoise」。应用界面首次启动时采用设备语言，之后可在设置中修改并保存偏好。

## AI 与隐私

AI 功能采用 **BYOK（自备 API 密钥）**。你可以选择服务商预设，或配置兼容服务的端点、模型和密钥。支持 OpenAI Compatible、OpenAI Responses 和 Anthropic Messages 协议。

AI 请求直接发送到你配置的服务商，费用由该服务商收取。执行分类、分组或拆解时，相关任务标题会发送给该服务；方寸不提供托管 AI 中转。普通待办无需账号、无需配置 AI，也可以离线使用。

任务、任务板和常规设置保存在设备本地，目前没有账号系统或自动云同步。API 密钥通过系统安全存储保存。备份默认不包含密钥；如果明确选择将密钥加入备份，文件中的密钥为明文，请妥善保管。详见 [AI 服务商说明](docs/AI_PROVIDER_PRESETS.md) 和 [备份格式说明](docs/BACKUP_FORMAT.md)。

## 获取与运行

目前可从源码构建；应用商店和预编译安装包尚未发布。项目持续维护 Android 和 Windows 客户端，暂不支持 iOS、macOS、Linux 或 Flutter Web。

### 环境要求

- Flutter **3.32.8**、Dart **3.8.1**
- Android：Android SDK 和 JDK
- Windows：Windows 主机以及 Visual Studio 的“使用 C++ 的桌面开发”工作负载

在仓库根目录运行：

```sh
flutter pub get
flutter devices
flutter run -d <device-id>
```

在 Windows 上启动桌面版本：

```sh
flutter run -d windows
```

### 检查与构建

```sh
flutter analyze --no-pub
flutter test --no-pub

# Android Release 构建
flutter build apk --release --no-tree-shake-icons

# Windows Release 构建
flutter build windows --release
```

Release 构建适合检查真实动画和交互性能。Android 构建中的 `--no-tree-shake-icons` 用于保留应用所需的 Material 图标字形。正式分发还需要正确配置 Android 签名；Windows 构建目前不提供 Authenticode 签名。详细步骤见 [开发指南](docs/DEVELOPMENT.md)。

## 项目结构

持续开发的应用使用 Flutter；Android 和 Windows 共用界面、数据模型与业务逻辑。早期 React、Tauri 和 Capacitor 原型保留在 `legacy/web/`，仅供参考，不再主动维护。

```text
lib/                 Flutter 应用与共享业务逻辑
android/             Android 平台工程
windows/             Windows 平台工程
assets/branding/     应用品牌素材
test/                单元测试与组件测试
integration_test/    集成测试
docs/                架构、开发、备份与服务商说明
legacy/web/          冻结的早期 Web 与桌面原型
```

## 参与项目

欢迎提交问题、分享使用反馈、改进翻译或贡献代码。提交问题时请说明平台、复现步骤和预期行为；请勿附上 API 密钥、真实备份或其他私人数据。

- [贡献指南](.github/CONTRIBUTING.md)
- [开发指南](docs/DEVELOPMENT.md)
- [文档索引](docs/README.md)

未来计划探索日计划功能，将已整理优先级的任务进一步安排到一天之中；当前版本尚未提供该功能。

## 许可

本项目按 [GNU General Public License v3.0 only](LICENSE) 发布。第三方依赖和素材遵循各自的许可。Flutter 3.32.8 随带的 Material Icons 字体许可文件为 CC BY 4.0；该许可允许商业使用，但要求保留署名和许可信息。Google 的 [Material Icons 指南](https://developers.google.com/fonts/docs/material_icons)目前标注 Apache 2.0。为覆盖随 Flutter SDK 提供的具体字体文件，本项目按 CC BY 4.0 保留署名及许可证，见 [第三方声明](assets/licenses/THIRD_PARTY_NOTICES.txt)和 [许可证全文](assets/licenses/MaterialIcons_LICENSE.txt)；两份文件也随应用资源分发。
