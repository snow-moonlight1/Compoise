# 方寸 · Compoise 商店介绍草稿

以下文案用于后续应用商店页面，正式提交前需按各商店字段限制和政策复核。

## 简短说明

中文：方寸是一款本地优先的四象限任务管理应用，帮助你理清轻重缓急，并可选用自带密钥的 AI 整理和拆解任务。

English: Compoise is a local-first Eisenhower task manager that helps you prioritize, focus, and optionally organize tasks with your own AI provider.

## 功能说明

- 按重要性和紧急性组织任务，并在总览与单象限聚焦之间切换。
- 用多个任务板区分工作、学习和个人计划。
- 将大任务拆成子项，添加笔记、截止日期和提醒。
- 按用户设置的阈值，根据截止日期调整任务紧急状态。
- 搜索任务与笔记，筛选任务并回顾已完成事项。
- 可选择配置自己的 AI 服务商，执行分类、分组和任务拆解。
- 在 Android 与 Windows 之间通过 JSON 文件手动转移备份。

## 数据说明

任务库保存在设备本地，不提供账号或自动云同步。普通任务管理可离线使用。调用 AI 时，相关任务文本会发送到用户配置的端点。默认备份省略 API 密钥；用户明确选择包含时，备份文件中的密钥为明文。详见 [隐私说明](PRIVACY_POLICY.md)。
