# 方寸 · Compoise 隐私说明 / Privacy Notice

本文说明当前开源客户端的数据处理行为；应用商店发行时仍需根据目标地区和商店要求复核。

## 中文

方寸当前提供 Flutter Android 与 Windows 客户端，以及 Linux 桌面预览版。任务、看板、备注、日程和普通设置保存在设备的应用数据中；任务库在本机没有应用层加密。方寸没有账号；同步是可选功能，默认关闭（见下文）。普通待办可离线使用。应用代码没有集成广告或行为分析 SDK。

用户填写的 AI API 密钥通过系统保护存储保存。Android 使用 Keystore，Windows 使用系统凭据保护与应用目录中的加密文件；Linux 使用 Secret Service，须配置并解锁默认密钥环。旧版本的明文配置在新存储写入并读回成功后才迁移清理；这不保证物理介质上已安全擦除。系统备份与设备迁移不保证凭据可用。

用户主动使用 AI 分类、分组或拆解时，应用把相关任务文本和提示词从本机发送到设置中的模型端点，并用密钥鉴权。预设端点使用 HTTPS；自定义端点可以是第三方代理或 HTTP，接收方和传输保护取决于用户配置。模型列表查询携带密钥，但不携带任务正文。应用当前没有自营的 AI 中转服务器。第三方端点的数据处理由其运营者决定。

JSON 备份是**明文文件**，包含任务、日程和配置，默认不含 API 密钥。只有每次导出时主动选择包含密钥并确认提示，文件才会带上**明文密钥**。覆盖导入默认保留本机密钥，替换它需要用户明确选择。请把备份当作敏感文件保管。

同步默认关闭。开启后，方寸把任务库同步到用户自己选择的存储：OneDrive 个人账户的应用文件夹（OneDrive 里显示为“应用/Compoise”，方寸看不到网盘里的其他文件），或用户填写的 WebDAV 服务器（例如坚果云、Nextcloud、群晖）。方寸没有自己的同步服务器，数据直接在设备和这些服务之间传输，由微软或 WebDAV 服务的运营者按其政策处理。使用 OneDrive 时，应用连接 `login.microsoftonline.com`（在系统浏览器里登录、刷新令牌）、`graph.microsoft.com`（读写文件），以及 OneDrive 为下载和上传给出的预授权地址。

同步的内容是任务板、任务、子项、日程和一部分外观与行为设置。API 密钥、网盘登录令牌和只属于这台设备的设置（视图模式、字号、字体、窗口位置、快捷键等）不同步。OneDrive 登录令牌、WebDAV 密码和由同步密码推导出的密钥只保存在系统安全存储里（与 API 密钥相同的方式），不写入同步文件或 JSON 备份；同步密码本身不保存。断开同步时删除这些凭据和本机的同步设置，任务不受影响。

不设同步密码时，同步文件只做 gzip 压缩，网盘服务商能读到任务内容。设置同步密码后，文件在本机用 Argon2id 推导出的密钥以 AES-256-GCM 加密后再上传，网盘里只有密文；服务商仍能看到文件名（随机生成的设备 ID）、文件大小和修改时间，以及只含库 ID 和加密参数的 `vault.json`。忘记同步密码时，网盘上的数据无法解密，本机数据不受影响。在微软账户里撤销方寸的授权后，已经拿到的访问令牌在过期前（通常不超过 1 小时）仍能使用。

截图导入在本机识别文字。识别模型在第一次使用时从本项目的发布地址下载（只下载模型文件，不上传任何内容）。用户选择的图片在本机识别，校对确认后仅将普通任务字段写库。Android 会逐张创建有界私有临时副本，识别后删除，退出或下次启动清理本模块残留；桌面读取所选原文件，不删除它们。原图和原始识别结果不进入任务库或日志，应用不上传截图。

Android 提醒可能使用通知、精确闹钟、开机恢复和震动权限；Windows 可使用本地通知、托盘和热键。Linux 预览版目前不会投递系统提醒通知。权限、系统设置和设备行为会影响 Android 与 Windows 的提醒送达。

Android 的提醒设置只在用户点击后申请权限：通知、准时提醒，以及让应用不受电池优化限制（`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`）。为了显示自启动是否已开启，应用会在本机读取小米 / Redmi / POCO 系统中本应用的自启动开关，并查询厂商自启动设置页是否存在；这些结果不离开设备。

应用在本机应用数据目录保留一份很小的诊断日志（最多几个轮换文件），记录提醒、托盘等功能的失败类型和未捕获的错误；开启同步后还记录同步状态和失败原因（失败类型、HTTP 状态与错误代码、请求方法和服务器主机名）。写入前会去掉密钥、网址、邮箱和系统用户名，不记录任务内容、文件路径、账号和令牌。日志不会自动上传；只有用户在设置中“导出诊断信息”并自行分享文件时，它才会离开设备。导出文件还包含版本、系统版本、界面设置、AI 预设与协议名称和任务数量。

“自动检查更新”默认关闭。开启后，应用每天最多一次向 GitHub（`api.github.com`）查询本项目的最新版本；这个接口拒绝或出错时（例如同一网络的查询太多），改为访问 `github.com` 上本项目的最新发布页，从跳转地址读出版本号。手动点“检查更新”也发送同样的请求。请求只带应用版本号，不含任务或个人信息；GitHub 会像处理其他网络请求一样看到你的 IP 地址。应用不会自动下载或安装更新。

## English

Compoise currently provides Flutter clients for Android and Windows, plus a Linux desktop preview. Tasks, boards, notes, schedules, and ordinary settings are stored in the app's local data. The task library has no application-level encryption on the device. Compoise has no account; sync is optional and off by default (see below). Ordinary task management works offline. The current app does not include advertising or behavioral analytics SDKs.

Your AI API key is kept in system-protected storage. Android uses Keystore; Windows uses system credential protection together with an encrypted file in the app directory. Linux uses Secret Service and requires a configured, unlocked default keyring. Older plaintext configuration is removed only after the new store has written and read the key successfully. This does not promise secure erasure of physical media. System backup or device migration may not restore the credential.

When you initiate AI classification, grouping, or decomposition, the app sends the relevant task text and prompt from your device to the model endpoint configured in Settings, using your key for authentication. Presets use HTTPS. A custom endpoint may be a third-party proxy or use HTTP, so its operator and your configuration determine the recipient and transport protection. Model discovery sends the key but no task body. The app currently operates no AI relay server. The endpoint operator controls its own data handling.

JSON backups are **plaintext** and include tasks, schedules, and configuration, without the API key by default. The key is included **in plaintext** only when you choose that option and confirm the warning on each export. Overwrite import keeps the device's current key by default; replacing it requires an explicit choice. Handle backups as sensitive files.

Sync is off by default. When you turn it on, Compoise syncs the task library to storage you choose: the app folder of a personal OneDrive account (shown in OneDrive as "Apps/Compoise"; Compoise cannot see the rest of your files), or a WebDAV server you enter (for example Nutstore, Nextcloud, or Synology). Compoise runs no sync server of its own. Data travels directly between your devices and these services, and Microsoft or the WebDAV operator handles it under their own policies. With OneDrive, the app connects to `login.microsoftonline.com` (sign-in in the system browser and token refresh), `graph.microsoft.com` (reading and writing files), and the pre-authenticated addresses OneDrive gives for downloads and uploads.

Sync covers boards, tasks, steps, schedules, and some appearance and behavior settings. API keys, storage sign-in tokens, and settings that belong to one device (view mode, font size, font, window position, hotkeys, and similar) are not synced. OneDrive tokens, the WebDAV password, and the key derived from the sync password are kept only in system-protected storage (the same way as the API key) and are never written to sync files or JSON backups. The sync password itself is not stored. Disconnecting deletes these credentials and the device's sync settings; tasks stay.

Without a sync password, sync files are only gzip-compressed, so the storage provider can read the tasks. With a sync password, files are encrypted on the device with AES-256-GCM, using a key derived with Argon2id, before upload, so the storage holds only ciphertext. The provider can still see file names (randomly generated device IDs), sizes, and modification times, plus `vault.json`, which holds only the library ID and encryption parameters. If you forget the sync password, the data in the storage cannot be decrypted; local data is unaffected. After you revoke Compoise's access in your Microsoft account, an access token already issued keeps working until it expires (usually within an hour).

Screenshot import recognizes text on the device. The recognition models are downloaded from this project's release locations the first time you use it (model files only; nothing is uploaded). Selected images are recognized on the device, and only ordinary task fields are saved after review. Android creates bounded private temporary copies one at a time, deletes them after recognition, and cleans this module's leftovers on exit or the next startup. Desktop clients read selected originals without deleting them. Original images and raw OCR results are not saved in the task library or logs. The app does not upload screenshots.

Android reminders may use notification, exact alarm, boot recovery, and vibration permissions. Windows can use local notifications, a tray icon, and hotkeys. The Linux preview does not currently deliver system reminder notifications. On Android and Windows, delivery depends on permissions, system settings, and device behavior.

On Android, reminder setup asks for permissions only after you tap it: notifications, exact alarms, and an exemption from battery optimization (`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`). To show whether autostart is on, the app reads this app's autostart switch on Xiaomi / Redmi / POCO devices and checks whether a vendor autostart settings page exists. These results stay on the device.

The app keeps a small diagnostics log in its local app data folder (a few rotating files) with the failure types of features such as reminders and the tray, and uncaught errors. With sync on, it also records sync status and why a round failed (failure type, HTTP status and error codes, request method, and server host name). Keys, web addresses, e-mail addresses, and system user names are removed before writing; task content, file paths, accounts, and tokens are not logged. The log is never uploaded; it leaves the device only if you choose "Export diagnostics" in Settings and share the file yourself. The exported file also lists the app and system versions, display settings, the AI preset and protocol names, and task counts.

"Check for updates automatically" is off by default. When you turn it on, the app asks GitHub (`api.github.com`) for this project's latest release at most once a day. If that API refuses or fails (for example, when too many requests come from the same network), the app opens this project's latest-release page on `github.com` instead and reads the version from the address it redirects to. Tapping "Check for updates" sends the same request. The request carries only the app version and no tasks or personal data. GitHub sees your IP address, as with any web request. The app never downloads or installs updates by itself.
