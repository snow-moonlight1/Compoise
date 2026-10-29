# Changelog

All notable changes to this project are recorded here. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Each version lists its changes in Chinese first and then in English. The GitHub release notes open with that version's entry, so it has to be complete before the release; see the [release process](docs/release-process.md).

本文件记录每个版本的主要变化，格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循[语义化版本](https://semver.org/lang/zh-CN/)。每个版本先用中文写（新增、变更、修复、维护、已知限制等），再用英文写同样的内容。GitHub Release 说明顶部的“更新 / What's new”直接取自这里，所以发版前必须写完整，见[发布流程](docs/release-process.md)。平时合并用户能看到的改动时，就把它补进 `Unreleased`。

## [Unreleased]

### 新增

- 首页四象限里可以拖动任务调整顺序：在同一象限里拖动可以换位置，拖到任意象限的两个任务之间会正好插在那里。拖动时其他任务会让出位置，空出来的地方就是松手后的落点。多选的一叠任务也一起插到那里。拖到另一个象限的空白处或标题上，仍然放到最上面。

### Added

- Tasks on the home four-quadrant view can be reordered by dragging: drag within a quadrant to change the order, or drop between two tasks in any quadrant to insert it exactly there. While you drag, the other tasks slide apart to show where it will land. A multi-selected stack is inserted there together. Dropping on another quadrant's blank area or title still puts the task at the top.

## [1.2.1] - 2026-10-26

这一版修复添加任务时的两个小问题：误关窗口不再丢失没写完的文字，按回车时键盘不再闪一下。This release fixes two small issues when adding tasks: text is no longer lost when the sheet is closed by accident, and the keyboard no longer flickers on Enter.

### 修复

- 添加任务时不小心点到空白处关掉了窗口，没写完的文字会保留，下次打开还在；添加成功后清空。文字只存在本机，不进入备份。
- 手动添加时在一行里按回车换到下一行，键盘不再先收起再弹出，窗口不再跳动。

### Fixed

- Unsent text in the add-task sheet is kept when the sheet is closed by accident and comes back next time; it is cleared once the task is added. It stays on this device and is not part of backups.
- Pressing Enter in a manual task line no longer hides and reshows the keyboard, so the sheet no longer jumps.

## [1.2.0] - 2026-10-20

这一版加入可选同步：用你自己的 OneDrive 或 WebDAV 网盘在设备之间同步任务，不需要方寸账号。This release adds optional sync between your devices through your own OneDrive or WebDAV storage, with no Compoise account.

### 新增

- **可选同步**（设置 → 同步，默认关闭）：任务板、任务、子任务、日程，以及语言、主题、紧急提醒天数等设置，会在你的设备之间同步。方寸没有自己的服务器，数据只放在你自己的网盘里。
- **OneDrive（推荐）**：点“登录 Microsoft 账号”，在浏览器里登录并同意授权即可，不用自己申请任何密钥。方寸只能读写 OneDrive 里的“应用/Compoise”文件夹，看不到网盘里的其他文件。
- **WebDAV（高级）**：坚果云、Nextcloud、群晖等支持 WebDAV 的网盘或 NAS，填写服务器地址、用户名和密码即可。坚果云要用第三方应用密码，设置页里有说明；地址用 http 时会提醒密码和文件以明文传输。
- **同步密码（可选）**：设置后，网盘里的同步文件会被加密（Argon2id 和 AES-256-GCM），只有输入同一密码的设备能读取。之后可以修改或取消密码，其他设备会提示输入新密码或确认。忘记密码无法找回，但可以在任一已连接的设备上重新设置。
- **加入已有的同步**：第二台设备连接同一个位置时，会找到已有的同步数据（加密时要输入同步密码），本机现有的任务和它合并，两边的任务都保留。
- **合并**：按字段合并，两台设备改了同一个任务的不同地方，两边的修改都保留；删掉的任务不会在别的设备上重新出现。离线时的修改按实际修改时间参与合并。
- **自动同步**：修改后、打开应用、回到前台和切到后台时同步，前台时每 10 分钟也同步一次；断网或服务器出错时自动延后重试，不打断操作。随时可以点“立即同步”。
- **状态和提示**：设置页显示上次同步时间；出问题时说明原因（例如登录失效、连不上服务器、网盘空间不足、请求被限制），并直接给出“重新登录”“输入新密码”等操作。
- **设备管理**：查看同步里的设备（名称、平台、最后上传时间），修改本机名称，移除不再使用的设备。
- **断开同步**：本机停止同步，任务保持不变；可以选择同时删除网盘里本机的同步文件。

### 变更

- 检查更新更可靠：GitHub 接口拒绝或出错时（例如同一网络的查询次数用完），改为访问 github.com 上的发布页读取最新版本。
- 诊断日志也记录同步状态和失败原因（失败类型、HTTP 状态和错误代码、请求方法和服务器主机名），方便排查问题；仍然不记录路径、账号、令牌和任务内容。

### 已知限制

- 一次只能连接一个同步位置。
- OneDrive 只支持个人 Microsoft 账户（outlook.com、hotmail.com、live.com 等），不支持工作或学校账户。
- 同一处在两台设备上同时修改时，保留较晚的修改，没有让你选择的界面。
- 不会同步：AI 服务的密钥和配置、网盘的登录信息、字体大小、视图模式、窗口和桌面设置。
- Linux 需要可用的系统钥匙串，才能保存同步的登录信息和密码。

### Added

- **Optional sync** (Settings → Sync, off by default): boards, tasks, subtasks, schedules, and settings such as language, theme and the urgency threshold are synced between your devices. Compoise runs no server; the data stays in your own storage.
- **OneDrive (recommended)**: tap "Sign in with Microsoft", sign in and allow access in the browser. There are no keys to set up. Compoise can only read and write its own Apps/Compoise folder and cannot see the rest of your files.
- **WebDAV (advanced)**: Nutstore, Nextcloud, Synology and other WebDAV storage or NAS, with a server address, user name and password. Nutstore needs a third-party app password, which the settings page explains. An http address shows a warning that the password and files travel unencrypted.
- **Sync password (optional)**: the synced files are encrypted (Argon2id and AES-256-GCM) so only devices with the same password can read them. You can change or remove the password later; other devices ask for the new password or a confirmation. A forgotten password cannot be recovered, but it can be set again on any connected device.
- **Joining an existing sync**: a second device that connects to the same location finds the existing data (asking for the sync password if it is encrypted) and merges it with its own tasks; both sides are kept.
- **Merging**: changes merge field by field, so edits to different parts of the same task on two devices are both kept, and deleted tasks do not come back on another device. Offline edits merge by the time they were made.
- **Automatic sync**: after edits, when the app opens, returns to the foreground or goes to the background, and every 10 minutes in the foreground. After network or server errors it retries later on its own without interrupting you. "Sync now" is always available.
- **Status and fixes**: the settings page shows the last sync time. When something goes wrong it says why (for example an expired sign-in, an unreachable server, a full storage quota or rate limiting) and offers the next step, such as "Sign in again" or entering the new password.
- **Devices**: see the devices in the sync (name, platform, last upload), rename this device and remove devices you no longer use.
- **Disconnect**: this device stops syncing and keeps its tasks; you can also delete this device's file from the storage.

### Changed

- More reliable update check: when the GitHub API refuses or fails (for example after too many requests from the same network), the app reads the latest version from the release page on github.com.
- The diagnostics log also records sync status and failures (failure type, HTTP status and error codes, request method and server host name) to help with bug reports. It still leaves out paths, accounts, tokens and task content.

### Known limitations

- One sync location at a time.
- OneDrive supports personal Microsoft accounts (outlook.com, hotmail.com, live.com and similar), not work or school accounts.
- When the same item changes on two devices at once, the later edit wins; there is no screen to choose between them.
- Not synced: AI service keys and configuration, storage sign-in details, font size, view mode, window and desktop settings.
- On Linux, saving the sync sign-in and password needs a working system keyring.

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

[Unreleased]: https://github.com/snow-moonlight1/Compoise/compare/v1.2.1...HEAD
[1.2.1]: https://github.com/snow-moonlight1/Compoise/releases/tag/v1.2.1
[1.2.0]: https://github.com/snow-moonlight1/Compoise/releases/tag/v1.2.0
[1.1.0]: https://github.com/snow-moonlight1/Compoise/releases/tag/v1.1.0
[1.0.1]: https://github.com/snow-moonlight1/Compoise/releases/tag/v1.0.1
[1.0.0]: https://github.com/snow-moonlight1/Compoise/releases/tag/v1.0.0
