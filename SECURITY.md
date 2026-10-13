# Security Policy / 安全策略

## Supported versions / 支持的版本

Only the latest release on the [Releases](https://github.com/snow-moonlight1/Compoise/releases) page receives security fixes.

只有 [Releases](https://github.com/snow-moonlight1/Compoise/releases) 页面上的最新版本会收到安全修复。

## Reporting a vulnerability / 报告漏洞

Please do **not** open a public issue with the details.

1. If the repository's **Security → Report a vulnerability** button is available, use it. The report stays private between you and the maintainer.
2. Otherwise, open an issue that only says you have a security report and asks [@snow-moonlight1](https://github.com/snow-moonlight1) for a private contact channel. Leave out every detail.

Describe the affected version and platform, the steps to reproduce, and the impact. Never include real API keys, backups or personal data. Use made-up data.

You can expect a first reply within 7 days.

请**不要**在公开 Issue 中写出漏洞细节：

1. 如果仓库的 **Security → Report a vulnerability** 可用，请通过它私下提交。
2. 否则请开一个只写"有安全问题需要私下联系"的 Issue，请 [@snow-moonlight1](https://github.com/snow-moonlight1) 提供私下联系方式，不要写任何细节。

报告中请写明受影响的版本、平台、复现步骤和影响范围，只使用虚构数据，不要附上真实 API 密钥、备份或个人数据。一般会在 7 天内首次回复。

## Scope / 范围

The app stores tasks locally. API keys are kept in the system's secure storage: Android Keystore, Windows credential protection, or the Linux Secret Service. AI requests go only to the endpoint the user configures. Reports about these areas are especially welcome:

- how API keys are stored and when they are written to backups;
- the import checks for backup files;
- the native OCR library and the model download, which is checked against a pinned SHA-256;
- release signing and the integrity of release files.

应用在本机保存任务，API 密钥存放在系统安全存储中（Android Keystore、Windows 凭据保护、Linux Secret Service），AI 请求只发往用户自己配置的地址。以下方面的报告尤其欢迎：

- 密钥的保存方式，以及什么情况下会写进备份；
- 备份文件的导入检查；
- 原生 OCR 库，以及按固定 SHA-256 校验的模型下载；
- 发行签名和发行文件的完整性。
