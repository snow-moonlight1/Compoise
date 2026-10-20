# Changelog

All notable changes to this project are recorded here. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Each version lists its changes in Chinese first and then in English. The GitHub release notes open with that version's entry, so it has to be complete before the release; see the [release process](docs/release-process.md).

本文件记录每个版本的主要变化，格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循[语义化版本](https://semver.org/lang/zh-CN/)。每个版本先用中文写（新增、变更、修复、维护、已知限制等），再用英文写同样的内容。GitHub Release 说明顶部的“更新 / What's new”直接取自这里，所以发版前必须写完整，见[发布流程](docs/release-process.md)。平时合并用户能看到的改动时，就把它补进 `Unreleased`。

## [Unreleased]

## [1.2.0] - 2026-10-20

### 新增

- 可选同步，默认关闭，不需要方寸账号或服务器。任务库放在你自己的存储里：
  - OneDrive 个人账户，在系统浏览器里登录。方寸只能访问它自己的应用文件夹（应用/Compoise）。
  - WebDAV（高级选项），例如坚果云、Nextcloud 或群晖。
- 可选的同步密码，对同步文件端到端加密（Argon2id 和 AES-256-GCM）。不设密码时文件只做压缩，存储服务商能看到内容。
- 按字段合并：两台设备改了同一个任务的不同字段，两边的修改都会保留；删掉的任务不会再出现。
- 设置 → 同步里可以看到同步库里的设备，给它们改名或移除。
- 修改后、打开应用和回到前台时自动同步，另有定时同步；连续失败后会等更久再试。随时可以点“立即同步”。

### 变更

- GitHub 接口拒绝或出错时（例如共享网络用完了每小时的查询次数），检查更新改为访问 github.com 上的发布页。
- 诊断日志也记录同步状态和失败原因：失败类型、HTTP 状态和错误代码、请求方法和服务器主机名。仍然不记录路径、账号、令牌和任务内容。

### 已知限制

- 一次只能连接一个同步位置。
- 不支持华为云空间，也不支持 OneDrive 的工作或学校账户。
- 同一个字段在两台设备上同时修改时，保留较晚的一份，没有让你选择的界面。
- API 密钥、网盘登录令牌和只属于本机的设置（视图模式、字号、窗口位置、快捷键等）不同步。
- Linux 需要可用的系统钥匙串来保存同步的登录信息和密钥。

### Added

- Optional sync, off by default and without a Compoise account or server. Your library goes to storage you already own:
  - OneDrive personal accounts, signed in through the system browser. Compoise can only reach its own app folder (Apps/Compoise).
  - WebDAV as an advanced option, for example Nutstore (坚果云), Nextcloud or Synology.
- An optional sync password encrypts the synced files end to end (Argon2id and AES-256-GCM). Without it the files are only compressed, so the storage provider can read them.
- Changes merge field by field: edits to different fields of the same task are both kept, and deleted tasks do not come back.
- Settings → Sync shows the devices in the library and lets you rename or remove them.
- Sync runs on its own after changes, when the app opens or returns to the foreground, and on a timer, and waits longer after repeated failures. "Sync now" is always available.

### Changed

- The update check asks the release page on github.com when the GitHub API refuses or fails, for example after its hourly limit on a shared network.
- The diagnostics log also records sync status and failures: the failure type, HTTP status and error codes, and the request method and server host name. It still leaves out paths, accounts, tokens and task content.

### Known limitations

- One sync location at a time.
- Huawei Cloud and OneDrive work or school accounts are not supported.
- When the same field changes on two devices at once, the later edit wins; there is no screen to choose between them.
- API keys, storage sign-in tokens and device-only settings (view mode, font size, window position, hotkeys and similar) are not synced.
- On Linux, saving the sync sign-in and key needs a working system keyring.

## [1.1.0] - 2026-10-19

### 新增

- 可选的计次待办：有限目标或无限累计，单独的“记录一次”操作，有限目标达到后自动完成，支持撤销。
- Android 可以把文字分享到方寸，逐行预览后手动添加；长按应用图标有“新建任务”和“今天”快捷方式。已有草稿打开时，分享的内容会等它处理完。
- Linux：应用运行时投递提醒，汇总错过的提醒（不重复），支持系统托盘和关闭到托盘，以及默认关闭的 XDG 登录启动。
- 备份格式 v4 保留计次进度；继续导入 v1/v2/v3 备份。导出到旧格式时，含计次的任务不会被悄悄丢掉进度。旧版应用不能导入 v4 备份。

### 变更

- Windows 全局快捷键恢复窗口后，直接打开新建任务的输入框。
- 周期待办暂缓；计次进度不会生成日程，也不改变任务的日期。

### Added

- Optional task count progress: a finite target or unlimited counting, a separate Record once action, automatic completion at the target, and Undo.
- Android text sharing into a manual multiline preview, plus New task / Today launcher shortcuts; shares wait while an existing draft is open.
- Linux reminders while the app runs, a deduplicated missed-reminder summary, system tray and close to tray, and opt-in XDG login startup.
- Backup format v4 preserves count progress; v1/v2/v3 imports remain supported and exports to older formats refuse to drop counters. Older app versions cannot import v4 backups.

### Changed

- Windows global quick capture now opens the new-task input after restoring the window.
- Calendar recurrence is deferred; count progress does not create calendar events or change task dates.


## [1.0.1] - 2026-10-19

### 新增

- 设置 → 帮助与关于：可选的每日检查更新（默认关闭，只向 GitHub 查询最新版本）、“检查更新”按钮和应用版本号。
- “导出诊断信息”保存一个文本文件，包含版本、系统信息和最近的错误，方便报告问题。不含密钥、网址、邮箱和任务内容。
- 整理和拆分任务时等待 AI 的时间可以选 30、60 或 120 秒。连接测试仍然最多等 30 秒。

### 变更

- 整理和拆分任务默认等待 60 秒（原来是 30 秒），超时提示会指向新的设置。
- 提醒和 Windows 托盘的失败也记进本机的小日志（内存加应用数据目录里几个轮换文件），写入前去掉敏感信息。

### 维护

- 版本号或构建号不大于之前所有正式版本时，拒绝发布。
- 文档与 1.0.0 对齐：今天页、提示、Android 提醒设置、隐私说明和测试名称。

### Added

- Settings → Help & About: an optional daily update check (off by default; it only asks GitHub for the latest release), a "Check for updates" button and the app version.
- "Export diagnostics" saves a text file with the version, system details and recent errors for bug reports. Keys, addresses, e-mail addresses and task content are left out.
- AI wait time (30, 60 or 120 seconds) for sorting and splitting tasks. Connection tests keep their own 30-second limit.

### Changed

- Sorting and splitting tasks now wait up to 60 seconds by default instead of 30, and the timeout message points to the new setting.
- Reminder and Windows tray failures are also kept in a small local log (memory, plus a few rotating files in the app data folder), with secrets removed.

### Maintenance

- Formal releases are refused when their version or build number is not greater than every earlier release.
- Documentation brought in line with 1.0.0: the Today page, notices, Android reminder setup, privacy notice and test names.

## [1.0.0] - 2026-10-15

First public release. 首个公开版本。

### 新增

- 四象限，可以在总览和单个象限聚焦之间切换；多个任务板；任务可以有子项、笔记、标签、截止日期和提醒。
- 动态紧急性：截止日期临近时，任务按你设置的阈值移到紧急一侧。
- 今天页汇总今天日程里的任务，以及今天到期或已过期的任务；勾选完成后先显示删除线，再从列表里移走。
- 日程页：日视图和周视图，可以给任务安排时间块，也可以添加独立的日程，支持时区。
- “截止与提醒”对话框，为任务、子项、新任务和 AI 输入保存精确的日期和时间。
- Android 在新手引导后进入提醒设置（可以跳过）：依次申请通知、精确闹钟和后台运行，提供厂商自启动页面的入口，并读取小米 / HyperOS 的自启动状态。之后可以在设置里重新打开。
- 自备 API 密钥的 AI：分类、分组和拆解任务，拆解结果填进打开的草稿。预设 DeepSeek、火山引擎和阿里云百炼，也支持 OpenAI Compatible、OpenAI Responses 或 Anthropic Messages 协议的自定义端点。只有一个“测试连接”按钮。
- 截图导入（PNG 和 JPG）：用 ncnn 和 PP-OCRv5 在本机识别。识别出的任务默认选中，保存前可以在校对列表里修改、取消选择、拆分或合并。原生库随安装包提供，模型在第一次使用时下载并校验 SHA-256。
- JSON 备份的导出和导入，任务库很大时可以分成多个文件。默认不含 API 密钥，除非你选择包含。
- 搜索、筛选和已完成视图。
- 多选：把选中的任务一起拖到另一个象限（手机上长按，桌面上用鼠标拖动）。
- 安静的提示：常规的成功不提示；其他提示一次显示一条，约 4 秒后关闭。滑动删除可以撤销。
- 简体中文、English 和日本語；主题色、字号、减少动态效果，以及可选的漫画描边和拟态风格。
- 桌面：键盘快捷键、鼠标拖放、右键菜单和可调整宽度的任务池。Windows 另有托盘图标、全局快捷键和关闭到托盘。
- 安装包：
  - Android：arm64-v8a、armeabi-v7a 和 universal APK。
  - Windows x64：安装程序和便携 ZIP。
  - Linux x64：DEB、RPM 和 AppImage。

### 已知限制

- Windows 版没有代码签名，第一次运行时 SmartScreen 可能会提示。
- Linux 版不投递定时提醒通知，也没有托盘图标和全局快捷键。
- 暂不构建 Windows ARM64。

### Added

- Eisenhower matrix with an overview and a single-quadrant focus mode, multiple boards, tasks with steps, notes, tags, deadlines and reminders.
- Dynamic urgency: tasks move to the urgent side as their deadline approaches, based on a threshold you set.
- Today page that gathers the tasks scheduled for today and the ones due today or overdue; ticking one off strikes it through before it leaves.
- Schedule page with day and week views, time blocks for tasks and standalone events, time-zone aware.
- "Deadline & reminder" dialog that saves an exact date and time for tasks, steps, new tasks and AI input.
- Android reminder setup after the tutorial, which can be skipped: asks in turn for notifications, exact alarms and background running, links to the vendor autostart page, and reads Xiaomi / HyperOS autostart status. It can be reopened from Settings.
- AI with your own API key: classify, group and break down tasks; a breakdown fills the open draft. Presets for DeepSeek, Volcengine and Alibaba Bailian, and custom endpoints using the OpenAI Compatible, OpenAI Responses or Anthropic Messages protocol. A single "Test connection" button.
- Screenshot import (PNG and JPG): on-device OCR with ncnn and PP-OCRv5. Recognized tasks start selected on a review list where you can edit, deselect, split or merge them before saving. The native library ships in the packages; the models download on first use and are checked against SHA-256.
- JSON backup export and import, including multi-file backups for large libraries. The API key is left out unless you choose to include it.
- Search, filters and a completed-tasks view.
- Multi-select: drag the selected tasks together onto another quadrant (long press on phones, mouse drag on desktop).
- Quiet notices: routine successes show nothing; the remaining notices appear one at a time and close after about 4 seconds. Deleting by swipe offers Undo.
- 简体中文, English and 日本語; theme colors, font size, reduced motion, and optional comic outline and neumorphic styles.
- Desktop: keyboard shortcuts, mouse drag and drop, context menus and a resizable task pool. Windows also gets a tray icon, a global hotkey and close to tray.
- Release packages:
  - Android: arm64-v8a, armeabi-v7a and universal APKs.
  - Windows x64: installer and portable ZIP.
  - Linux x64: DEB, RPM and AppImage.

### Known limitations

- Windows builds are not code-signed, so SmartScreen may warn on first launch.
- The Linux version does not deliver scheduled reminder notifications, and it has no tray icon or global hotkey.
- Windows ARM64 is not built yet.

[Unreleased]: https://github.com/snow-moonlight1/Compoise/compare/v1.2.0...HEAD
[1.2.0]: https://github.com/snow-moonlight1/Compoise/releases/tag/v1.2.0
[1.1.0]: https://github.com/snow-moonlight1/Compoise/releases/tag/v1.1.0
[1.0.1]: https://github.com/snow-moonlight1/Compoise/releases/tag/v1.0.1
[1.0.0]: https://github.com/snow-moonlight1/Compoise/releases/tag/v1.0.0
