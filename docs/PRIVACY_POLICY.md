# MatrixFlow AI 隐私政策 / Privacy Policy

> **生效日期 / Effective Date**: 2026-09-16  
> **版本 / Version**: 1.0.0

---

## 中文版 (Chinese Version)

MatrixFlow AI（以下简称“我们”或“本应用”）是一款致力于保护用户隐私的**纯本地离线（Local-First）**艾森豪威尔四象限待办管理应用。我们深知个人数据与待办事项的重要性，因此在设计之初便确立了“**零数据收集、100% 用户自主掌控**”的核心安全原则。

请您仔细阅读本隐私政策以了解我们如何对待您的数据。

### 1. 数据存储与本地优先原则
- **100% 纯本地存储**：您的所有待办任务、子任务、备注、四象限分类、自定义看板、已完成历史与统计数据，均直接存储在您设备的本地存储空间中（通过 `SharedPreferences` 持久化）。
- **无中央服务器**：本应用不设立任何用户账户系统，无中央后端服务器，不记录、不接收、也不转存您的任何待办内容。
- **完全离线可用**：在没有任何网络连接的情况下，本应用的所有基础待办管理、排序、筛选与统计功能均可完整使用。

### 2. BYOK 自带密钥与 AI 服务直连
- **BYOK 机制（Bring Your Own Key）**：本应用支持用户自主输入大语言模型服务商（包括 DeepSeek、火山引擎、阿里云百炼或任何 OpenAI 兼容协议服务商）的 API Key。
- **端到端直接通信**：当您发起 AI 任务智能分类、自动分组或长期目标拆解时，请求将通过强加密的 HTTPS 协议**直接从您的设备发送给您指定的服务商官方接口**。
- **绝不中转密钥与待办**：MatrixFlow 团队绝无任何私有代理或数据抓取服务器，绝不收集、上传或转售您的 API Key 或待办内容。您的密钥仅以安全明文持久化在本地设备沙盒中。

### 3. 零遥测与零第三方追踪
- **无广告 SDK**：应用内不包含任何商业广告组件或广告联盟 SDK。
- **无分析埋点 SDK**：本应用未集成 Google Analytics、Firebase Analytics、友盟、TalkingData 等任何第三方用户行为追踪或崩溃统计工具。
- **静默运行**：我们不记录您的设备型号、IMEI、MAC 地址、剪贴板内容或网络运行日志。

### 4. 权限使用与合规说明
为了实现本地待办提醒与手势震动反馈，应用可能向系统申请以下必要权限，我们承诺绝不越权滥用：

| 权限名称 | 平台 | 用途说明 | 必要性与合规保障 |
|---|---|---|---|
| `INTERNET` | Android / Windows | 访问网络 | 仅用于用户主动触发 AI 功能时直连模型服务商 API；离线待办完全无需网络。 |
| `POST_NOTIFICATIONS` | Android | 显示系统通知 | 用于待办设定的截止时间与自定义提醒时刻触发横幅提醒。用户可随时在系统设置中关闭。 |
| `SCHEDULE_EXACT_ALARM` | Android | 精确闹钟排期 | 用于在指定时间点准时触发提醒。本应用**坚决不使用**高危的 `USE_EXACT_ALARM` 权限，完全符合应用商店合规审查。 |
| `RECEIVE_BOOT_COMPLETED` | Android | 开机自启广播 | 仅用于手机重启后重新向系统注册尚未到期的待办定时提醒，绝不用于后台常驻偷跑。 |
| `VIBRATE` | Android | 震动控制 | 用于到期提醒震动提示以及任务长按拖拽时的轻微触觉反馈。 |

### 5. 数据导出与备份控制
- 用户可随时使用内置的「数据备份」功能将全部待办与看板导出为标准 JSON 格式。导出的文件完全归用户个人掌控，由用户决定保存位置或通过何种网盘传输。

### 6. 联系我们
如果您对本隐私政策有任何疑问或改进建议，欢迎通过 GitHub 仓库提交 Issue 或 Pull Request：  
GitHub: [https://github.com/matrixflow/matrixflow](https://github.com/matrixflow/matrixflow)

---

## English Version

MatrixFlow AI ("we", "us", or "the app") is a **Local-First, privacy-centric** Eisenhower Matrix task management application. We believe your tasks, notes, and personal data belong exclusively to you. MatrixFlow is architected with a strict **Zero-Data Collection, 100% User-Owned** philosophy.

### 1. Data Storage & Local-First Philosophy
- **100% On-Device Storage**: All tasks, subtasks, notes, quadrant categories, custom boards, and completion stats are stored locally on your device (via secure platform storage).
- **No Central Servers**: There are no user accounts, no login walls, and no central servers operated by MatrixFlow. We never receive, inspect, or retain your task contents.
- **Full Offline Availability**: Core productivity features operate completely without an active internet connection.

### 2. BYOK (Bring Your Own Key) & Direct AI Connections
- **BYOK Architecture**: Users provide their own API Keys for AI model providers (such as DeepSeek, Volcengine, Alibaba Bailian, OpenAI, or custom compatible endpoints).
- **End-to-End Direct Transmission**: When you use AI task classification or goal decomposition, your device communicates **directly with the designated provider's official API** over HTTPS.
- **Zero Proxy or Intermediary**: MatrixFlow never routes, intercepts, proxies, or stores your API keys or prompts on any intermediary server. Keys remain encrypted or sandboxed on your local hardware.

### 3. Zero Telemetry & Zero Third-Party Tracking
- **No Ads**: The application contains no advertising SDKs or tracking pixels.
- **No Analytics**: We do not integrate telemetry SDKs such as Firebase Analytics, Umeng, or Mixpanel.
- **No Fingerprinting**: We do not collect device identifiers (IMEI, MAC address, IDFA) or browser history.

### 4. Permissions & Compliance
We request only the minimal permissions strictly necessary to deliver productivity features:

| Permission | Platform | Purpose | Compliance Guarantee |
|---|---|---|---|
| `INTERNET` | Android / Windows | Network Access | Strictly utilized when sending user-initiated AI requests to chosen providers. |
| `POST_NOTIFICATIONS` | Android | Show Notifications | Used to display task reminder banners at scheduled times. Can be toggled in system settings. |
| `SCHEDULE_EXACT_ALARM` | Android | Exact Scheduling | Triggers task reminders accurately on time. MatrixFlow **strictly avoids `USE_EXACT_ALARM`** to remain fully compliant with Google Play and app store guidelines. |
| `RECEIVE_BOOT_COMPLETED` | Android | Reschedule on Reboot | Restores active reminders after a device restart; no persistent background bloat. |
| `VIBRATE` | Android | Haptic Feedback | Provides subtle haptic sensations during drag-and-drop and alarms. |

### 5. Data Backup & User Ownership
You can export and import your tasks at any time in transparent JSON format. You retain complete ownership over where your backup archives are saved.

### 6. Contact & Open Source Inquiries
For questions or suggestions regarding privacy, please visit our open-source project repository:  
GitHub: [https://github.com/matrixflow/matrixflow](https://github.com/matrixflow/matrixflow)
