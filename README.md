<p align="center">
  <img src="assets/branding/rounded_rectangle_logo.png" alt="方寸 · Compoise app icon" width="132" />
</p>

<h1 align="center">方寸 · Compoise</h1>

<p align="center"><strong>方寸之间，理清轻重缓急。</strong></p>

<p align="center">简体中文 · <a href="README.en.md">English</a></p>

<p align="center">
  <a href="LICENSE"><img alt="License: GPL-3.0-only" src="https://img.shields.io/badge/License-GPL--3.0--only-3b82f6?style=for-the-badge" /></a>
  <img alt="Flutter" src="https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white" />
  <img alt="Dart" src="https://img.shields.io/badge/Dart-0175C2?style=for-the-badge&logo=dart&logoColor=white" />
  <img alt="Android" src="https://img.shields.io/badge/Android-3DDC84?style=for-the-badge&logo=android&logoColor=white" />
  <img alt="Windows" src="https://img.shields.io/badge/Windows-0078D6?style=for-the-badge&logo=windows&logoColor=white" />
  <img alt="Linux preview" src="https://img.shields.io/badge/Linux-preview-FCC624?style=for-the-badge&logo=linux&logoColor=black" />
</p>

方寸（Compoise）是一款本地优先的任务管理应用，支持 Android、Windows 和 Linux。它以艾森豪威尔四象限为核心，帮你理清轻重缓急、安排每天的时间，并可以用你自己的 AI 服务整理和拆解任务。

## 功能

| 功能 | 说明 |
| --- | --- |
| 四象限与聚焦 | 按重要和紧急整理任务，在总览和单个象限之间切换。 |
| 多任务板 | 把工作、学习和个人计划分开放。 |
| 父任务与子项 | 拆分大任务，给任务加笔记、标签、截止日期和提醒。 |
| 今天待办 | 汇总今天日程中的任务，以及今天到期或已过期的任务。 |
| 日程 | 日视图和周视图，可以给任务安排时间块，也可以添加独立的日程事件。 |
| 动态紧急性 | 根据截止日期和你设置的天数自动调整紧急程度，不需要 AI。 |
| AI 整理 | 自备 API 密钥，对任务分类、编组，或把大目标拆成子项。 |
| 截图识别导入 | 选择待办清单的截图，在本机识别文字，校对后一次导入。识别模型在第一次使用时下载。 |
| 查找与回顾 | 搜索任务和笔记、按条件筛选、查看已完成事项。 |
| 外观 | 简体中文、English、日本語；主题色、字体大小、减少动画，以及可选的漫画描边和拟态风格。 |
| 桌面操作 | 键盘快捷键、鼠标拖放和右键菜单；Windows 另有系统托盘和全局快捷键。 |
| 备份 | 导出和导入 JSON 文件，在设备之间转移数据。 |

## 下载

在 [Releases](https://github.com/snow-moonlight1/Compoise/releases) 页面下载最新版本：

| 平台 | 文件 |
| --- | --- |
| Android | `compoise-<版本>-android-arm64-v8a.apk`（大多数手机）、`…-armeabi-v7a.apk`（较旧的 32 位手机）、`…-universal.apk`（包含所有架构） |
| Windows x64 | `compoise-<版本>-windows-x64-setup.exe`（安装版）或 `…-windows-x64-portable.zip`（便携版，解压即用） |
| Linux x64 | `compoise-<版本>-linux-amd64.deb`、`…-linux-x86_64.rpm` 或 `…-linux-x86_64.AppImage` |

`SHA256SUMS.txt` 里是所有文件的校验值。

**Windows 提示**：程序目前没有代码签名，第一次运行时可能出现“Windows 已保护你的电脑”。确认文件来自本仓库的 Releases 页面后，点击 **“更多信息”**，再点击 **“仍要运行”**。

**Windows 数据位置**：任务和设置保存在 `%APPDATA%\Compoise\Compoise\`，API 密钥经系统加密保存在同一目录。便携版的解压目录里不保存数据，升级时直接换成新目录即可。卸载后如果想一并删除数据，请删除 `%APPDATA%\Compoise` 文件夹。

**Linux 依赖**：DEB 和 RPM 会自动安装依赖。AppImage 需要你自己安装：

```sh
sudo apt install libgtk-3-0 libsecret-1-0 libayatana-appindicator3-1 zenity fonts-noto-cjk libfuse2
```

- 新版 Debian/Ubuntu 上，`libfuse2` 的包名是 `libfuse2t64`。
- 保存 API 密钥需要一个已解锁的密钥环，例如 GNOME Keyring 或 KWallet。没有密钥环时，任务照常保存，只是不能用 AI。
- Linux 版目前还不会按时弹出提醒通知，也没有托盘和全局快捷键。

## AI 与隐私

- AI 功能需要自备 API 密钥（BYOK）。你可以选择服务商预设，也可以自己填写兼容服务的地址、模型和密钥。支持 OpenAI Compatible、OpenAI Responses 和 Anthropic Messages 三种协议。
- 只有在你使用分类、编组或拆解时，相关任务的文字才会发给你配置的服务商，费用也由服务商收取。方寸没有自己的 AI 中转服务器。
- 任务、任务板和设置都保存在本机，没有账号，也没有自动云同步。
- API 密钥保存在系统安全存储里。备份默认不包含密钥；如果你选择把密钥一起备份，文件里的密钥是明文。
- 截图识别完全在本机进行，不会上传图片。

详见[隐私说明](docs/privacy-policy.md)。

## 从源码构建

### 环境要求

- Flutter **3.32.8** stable（Dart 3.8.1）。版本固定在 `toolchain.json` 和 `.flutter-version` 中，CI 会检查。
- Android：Android SDK、JDK 17。
- Windows：Visual Studio 2022 的“使用 C++ 的桌面开发”。
- Linux：`clang cmake ninja-build pkg-config libgtk-3-dev libsecret-1-dev libayatana-appindicator3-dev`。

### 运行

```sh
flutter pub get
flutter run -d <设备 ID>     # 用 flutter devices 查看，例如 windows、linux 或手机
```

### OCR 原生库

截图识别用到一个 C++ 原生库（`native/ocr/`，基于 ncnn 和 PP-OCRv5）。不编译它，应用也能正常运行，只是截图识别入口会提示暂不可用。

- 模型文件不放进安装包。应用第一次识别时，从本仓库的 `ocr-models-v1` Release 下载模型，并按固定的 SHA-256 校验。
- 编译原生库需要先准备 ncnn，具体步骤见[开发指南](docs/development.md#ocr-原生库)。

更多内容见[开发指南](docs/development.md)，包括检查、测试、发行构建和 Android 签名。

## 项目结构

```text
lib/                 Flutter 应用：界面、数据模型和业务逻辑
  screens/           页面
  widgets/           可复用组件
  planner/           日程页
  import_preview/    截图导入的校对页
  screenshot_import/ 截图识别流程
  ocr/               OCR 原生库接口与模型下载
  services/          提醒、桌面外壳等平台服务
  experiments/       未接入正式应用的实验代码
native/ocr/          OCR 原生库（C++，ncnn + PP-OCRv5）
android/ windows/ linux/   各平台工程
test/                单元测试和组件测试
integration_test/    集成测试
scripts/ tool/       构建、发行和诊断脚本
docs/                项目文档
legacy/web/          早期 Web 原型，已冻结，只作参考
```

各模块之间怎么配合，见[架构说明](docs/architecture.md)。

## 参与贡献

欢迎报告问题、提建议、改进翻译或提交代码。请先阅读[贡献指南](CONTRIBUTING.md)和[行为准则](CODE_OF_CONDUCT.md)。安全问题请按[安全策略](SECURITY.md)私下报告。

- [文档目录](docs/README.md)
- [更新日志](CHANGELOG.md)
- [路线图](docs/roadmap.md)

## 许可

© 2026 Compoise contributors。本项目按 [GNU General Public License v3.0 only](LICENSE) 发布。第三方依赖和素材遵循各自的许可，见[第三方声明](assets/licenses/THIRD_PARTY_NOTICES.txt)。Flutter 3.32.8 自带的 Material Icons 字体按 CC BY 4.0 保留署名和许可证，全文见 [MaterialIcons_LICENSE.txt](assets/licenses/MaterialIcons_LICENSE.txt)。OCR 相关的第三方许可见 [native/ocr/THIRD_PARTY_OCR_NOTICES.md](native/ocr/THIRD_PARTY_OCR_NOTICES.md)。
