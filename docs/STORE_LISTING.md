# MatrixFlow AI 商店物料草稿

**尚未上架或送审。** 包名、开发者身份、隐私政策公开地址、截图、正式签名和设备验收都要由持有人确认。不得直接复制本草稿发布。当前 Android `applicationId` 是 `com.matrixflow.app`；Windows 发行身份见 [OS26 记录](OS26_NOTES.md)。

## 候选简短说明

中文：本地优先的四象限待办，支持看板、提醒和自带密钥 AI 辅助。

English: Local-first Eisenhower task app with boards, reminders, and optional bring-your-own-key AI.

## 候选功能说明

- 四象限任务、父子任务、完成历史、搜索、看板，以及宫格和列表视图。
- 任务截止日期与可选系统提醒。实际送达受设备权限和系统行为影响。
- 自带密钥 AI 分类、分组、拆解。发起请求时，相关任务文本和提示词发送到用户配置的模型端点；自定义地址可能是第三方代理或 HTTP。普通待办无需网络。
- Windows 桌面支持托盘、通知和快捷键。Android 与 Windows 使用同一份 v2 JSON 备份格式。
- 备份文件是明文，默认省略 API 密钥；每次明确选择包含后，文件才包含明文密钥。任务库没有应用层加密或自动云同步。详见 [隐私说明](PRIVACY_POLICY.md)。

## 上架前待补

1. 确认 Android 包名、正式签名和 Windows 发行身份；完成覆盖升级及双端人工检查。
2. 配置真实公开仓库、问题反馈、安全联系和可访问的隐私说明 URL。当前仓库没有 remote，不能填写推测的 GitHub 地址。
3. 用实际发行版本拍摄 Android 和 Windows 截图，核对本页功能与设备行为。不要展示已删除的命令台或完成率统计图。
4. 根据目标商店当时的表单和政策另行填写权限声明、数据处理与具体版本更新说明；本地源代码审计不能代替商店审查。
