# 方寸 · Compoise 隐私说明 / Privacy Notice

本文说明当前开源客户端的数据处理行为；应用商店发行时仍需根据目标地区和商店要求复核。

## 中文

方寸当前提供 Flutter Android 与 Windows 客户端，以及 Linux 桌面预览版。任务、看板、备注和普通设置保存在设备的应用数据中；任务库没有应用层加密，也没有账号或自动云同步。普通待办可离线使用。应用代码没有集成广告或行为分析 SDK。

用户填写的 AI API 密钥通过系统保护存储保存。Android 使用 Keystore，Windows 使用系统凭据保护与应用目录中的加密文件；Linux 使用 Secret Service，须配置并解锁默认密钥环。旧版本的明文配置在新存储写入并读回成功后才迁移清理；这不保证物理介质上已安全擦除。系统备份与设备迁移不保证凭据可用。

用户主动使用 AI 分类、分组或拆解时，应用把相关任务文本和提示词从本机发送到设置中的模型端点，并用密钥鉴权。预设端点使用 HTTPS；自定义端点可以是第三方代理或 HTTP，接收方和传输保护取决于用户配置。模型列表查询携带密钥，但不携带任务正文。应用当前没有自营的 AI 中转服务器。第三方端点的数据处理由其运营者决定。

默认 v2 JSON 备份是**明文文件**，包含任务和配置，但省略 `customApiKey`。每次明确选择包含凭据并确认提示后，文件才会加入**明文密钥**。旧 v1/v2 含密钥文件仍可导入；覆盖导入默认保留本机密钥，替换它需要用户明确选择。请按敏感文件保管备份。

Android 提醒可能使用通知、精确闹钟、开机恢复和震动权限；Windows 可使用本地通知、托盘和热键。Linux 预览版目前不会投递系统提醒通知。权限、系统设置和设备行为会影响 Android 与 Windows 的提醒送达。

## English

Compoise currently provides Flutter clients for Android and Windows, plus a Linux desktop preview. Tasks, boards, notes, and ordinary settings are stored in the app's local data. The task library has no application-level encryption, account, or automatic cloud sync. Ordinary task management works offline. The current app does not include advertising or behavioral analytics SDKs.

Your AI API key is kept in system-protected storage. Android uses Keystore; Windows uses system credential protection together with an encrypted file in the app directory. Linux uses Secret Service and requires a configured, unlocked default keyring. Older plaintext configuration is removed only after the new store has written and read the key successfully. This does not promise secure erasure of physical media. System backup or device migration may not restore the credential.

When you initiate AI classification, grouping, or decomposition, the app sends the relevant task text and prompt from your device to the model endpoint configured in Settings, using your key for authentication. Presets use HTTPS. A custom endpoint may be a third-party proxy or use HTTP, so its operator and your configuration determine the recipient and transport protection. Model discovery sends the key but no task body. The app currently operates no AI relay server. The endpoint operator controls its own data handling.

The default v2 JSON backup is **plaintext** and includes tasks and configuration, but omits `customApiKey`. The key is included **in plaintext** only when you explicitly select that option and confirm its warning on each export. Older v1/v2 backups containing keys remain readable. Overwrite import keeps the device's current key by default; replacing it requires an explicit choice. Handle backups as sensitive files.

Android reminders may use notification, exact alarm, boot recovery, and vibration permissions. Windows can use local notifications, a tray icon, and hotkeys. The Linux preview does not currently deliver system reminder notifications. On Android and Windows, delivery depends on permissions, system settings, and device behavior.
