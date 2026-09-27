# 贡献指南

感谢你愿意帮助改进方寸 · Compoise。项目当前维护 Flutter Android 与 Windows 客户端；`legacy/web/` 是冻结原型，请不要把它当作持续开发主线。

## 提交改动

1. 先搜索现有 Issue，避免重复报告。报告问题时请提供平台、应用版本、复现步骤和预期结果；不要附上 API 密钥、真实任务备份或个人日志。
2. 控制改动范围。Android 与 Windows 共用的业务逻辑放在 Flutter Store 或服务中，平台差异放在平台适配层。
3. 用户可见文案同步更新 `lib/l10n.dart` 中的 English、简体中文和日本語版本。
4. 提交前运行 `flutter analyze --no-pub` 与 `flutter test --no-pub`；涉及平台工程时，也请构建并手动验证对应平台。
5. Pull Request 请说明问题、行为变化、验证结果和未覆盖的平台情况。

## 安全与隐私

API 密钥、Android 发布签名、keystore、带密钥备份和真实用户任务数据都不得提交。测试使用合成数据。Android 签名配置可参考 `android/key.properties.example`；真实配置应保存在被 Git 忽略的本机文件或 CI secret 中。

项目按 GPL-3.0-only 发布。新增依赖或素材时，请确认其许可证兼容并在改动中说明来源。
