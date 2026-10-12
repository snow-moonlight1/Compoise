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
  <img alt="Linux preview" src="https://img.shields.io/badge/Linux-preview-FCC624?style=for-the-badge&logo=linux&logoColor=black" />
</p>

方寸（Compoise）是一款面向 Android 和 Windows 的本地优先任务管理应用，另提供 Linux 桌面预览版。它以艾森豪威尔四象限为核心，帮助你理清任务优先级、专注处理眼前事项，并在需要时使用 AI 整理和拆解任务。

*Compoise is a local-first task manager for Android and Windows, with a Linux desktop preview. Organize work with an Eisenhower matrix, focus on one quadrant, and optionally use your own AI provider to classify, group, and break down tasks.*

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
| 手动备份         | 通过 JSON 文件导入和导出数据，在支持的平台之间转移。 |

Android 桌面图标下方的应用名会按系统语言显示为「方寸」或「Compoise」。应用界面首次启动时采用设备语言，之后可在设置中修改并保存偏好。

## AI 与隐私

AI 功能采用 **BYOK（自备 API 密钥）**。你可以选择服务商预设，或配置兼容服务的端点、模型和密钥。支持 OpenAI Compatible、OpenAI Responses 和 Anthropic Messages 协议。

AI 请求直接发送到你配置的服务商，费用由该服务商收取。执行分类、分组或拆解时，相关任务标题会发送给该服务；方寸不提供托管 AI 中转。普通待办无需账号、无需配置 AI，也可以离线使用。

任务、任务板和常规设置保存在设备本地，目前没有账号系统或自动云同步。API 密钥通过系统安全存储保存。备份默认不包含密钥；如果明确选择将密钥加入备份，文件中的密钥为明文，请妥善保管。

## 获取与运行

目前可从源码构建；应用商店和预编译安装包尚未发布。Android 和 Windows 是持续维护的平台。Linux 桌面预览版已在 Ubuntu 24.04（WSL2/WSLg）完成构建、启动和核心流程测试；Linux 暂无系统提醒通知、托盘和全局快捷键。iOS、macOS 和 Flutter Web 尚未适配。

### 环境要求

- Flutter **3.32.8**、Dart **3.8.1**
- Android：Android SDK 和 JDK
- Windows：Windows 主机以及 Visual Studio 的“使用 C++ 的桌面开发”工作负载
- Linux：clang、CMake、Ninja 以及 GTK 3、libsecret、Ayatana AppIndicator 开发包（见下方“Linux 依赖”）

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

在 Linux 上运行预览版：

```sh
flutter run -d linux
```

检查、Release 构建和签名步骤见 [开发指南](docs/DEVELOPMENT.md)。

### Windows 便携版

**安装**：下载 `compoise-vX.Y.Z+N-windows-portable.zip`，解压到任意目录，运行其中的 `compoise.exe`。无需安装程序，也不写注册表启动项。请保持解压目录完整，不要只复制 exe。

**数据位置**：任务、任务板和设置保存在 `%APPDATA%\Compoise\Compoise\`；API 密钥以系统加密方式保存在同一目录，加密密钥存于 Windows 凭据管理器。解压目录本身不保存数据，因此升级时删除旧目录、解压新版即可。

**卸载**：在托盘图标菜单中选择“退出”，然后删除解压目录。如需一并删除数据，再删除 `%APPDATA%\Compoise` 文件夹，并在“控制面板 → 凭据管理器 → Windows 凭据”中删除与 Compoise 相关的条目。建议先在“设置 → 导出 JSON”备份。

**SmartScreen 提示**：目前 Windows 程序尚未进行代码签名，首次运行时可能出现“Windows 已保护你的电脑”。确认文件来自本仓库的 Releases 页面后，点击提示中的 **“更多信息”**，再点击 **“仍要运行”**。如果 zip 被标记为来自网络，也可以在解压前右键 zip → 属性 → 勾选“解除锁定”。

### Linux 依赖

以 Debian / Ubuntu 为例，运行预览版需要：

```sh
sudo apt install libgtk-3-0 libsecret-1-0 libayatana-appindicator3-1 fonts-noto-cjk
```

从源码构建还需要 `clang cmake ninja-build pkg-config libgtk-3-dev libsecret-1-dev libayatana-appindicator3-dev`。

- **GTK 3**：界面运行所需。
- **libsecret**：通过 Secret Service（如 GNOME Keyring、KWallet）保存 API 密钥。
- **AppIndicator**：托盘相关组件依赖。
- **中文字体**：系统缺少中文字体时界面会显示方块，请安装 `fonts-noto-cjk` 或其他 CJK 字体。
- **密钥环（可选）**：没有可用的密钥环时，任务和设置照常保存，只是无法保存 API 密钥、AI 功能不可用，应用会给出一次简短提示。
- **安装包**：DEB 和 RPM 已把中文字体（`fonts-noto-cjk` / `google-noto-sans-cjk-fonts`）设为推荐依赖，默认会一起安装。AppImage 不会自动安装依赖，请按上面的命令自行安装中文字体；运行 AppImage 还需要 `libfuse2`（Debian/Ubuntu 新版为 `libfuse2t64`）。

## 代码签名策略（计划中）

Windows 程序的代码签名**仍在计划中，目前发布的程序未签名**。计划申请 [SignPath Foundation](https://signpath.org) 的开源项目计划获得免费签名（由 [SignPath.io](https://signpath.io) 提供），获批后本节会更新为正式策略：

- 提交者与审核者：[@snow-moonlight1](https://github.com/snow-moonlight1)
- 批准者：[@snow-moonlight1](https://github.com/snow-moonlight1)
- 只对本仓库 GitHub Actions 发布工作流从带标签提交构建的 Windows 程序签名，每次签名都由人工批准。
- 隐私：除非用户主动请求，本程序不会向其他网络系统传输任何信息。使用 AI 功能时，相关任务文本会发送到你自己配置的模型端点。详见 [隐私说明](docs/PRIVACY_POLICY.md)。

## 项目结构

持续开发的应用使用 Flutter；Android、Windows 和 Linux 共用界面、数据模型与业务逻辑。早期 React、Tauri 和 Capacitor 原型保留在 `legacy/web/`，仅供参考，不再主动维护。

```text
lib/                 Flutter 应用与共享业务逻辑
android/             Android 平台工程
windows/             Windows 平台工程
linux/               Linux 桌面平台工程
assets/branding/     应用品牌素材
test/                单元测试与组件测试
integration_test/    集成测试
docs/                架构、开发、备份与服务商说明
legacy/web/          冻结的早期 Web 与桌面原型
```

## 参与项目

欢迎提交问题、分享使用反馈、改进翻译或贡献代码。提交问题时请说明平台、复现步骤和预期行为；请勿附上 API 密钥、真实备份或其他私人数据。

- [贡献指南](.github/CONTRIBUTING.md)
- [文档导航](docs/README.md)

后续功能、发行进度与 UI 实验见 [工作包状态](docs/ROADMAP.md)。

## 许可

© 2026 Compoise contributors。本项目按 [GNU General Public License v3.0 only](LICENSE) 发布。第三方依赖和素材遵循各自的许可。Flutter 3.32.8 随带的 Material Icons 字体许可文件为 CC BY 4.0；该许可允许商业使用，但要求保留署名和许可信息。Google 的 [Material Icons 指南](https://developers.google.com/fonts/docs/material_icons)目前标注 Apache 2.0。为覆盖随 Flutter SDK 提供的具体字体文件，本项目按 CC BY 4.0 保留署名及许可证，见 [第三方声明](assets/licenses/THIRD_PARTY_NOTICES.txt)和 [许可证全文](assets/licenses/MaterialIcons_LICENSE.txt)；两份文件也随应用资源分发。
