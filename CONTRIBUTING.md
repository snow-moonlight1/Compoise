# 参与 MatrixFlow AI

当前客户端是 `matrixflow-native/` 的 Flutter Android 与 Windows。根目录 React、Tauri、Capacitor 冻结，日常改动不要改那些目录。

## 联系与问题跟踪

本仓库没有 git remote，也没有已配置的维护者邮箱。公开的 Issue、Pull Request 和安全邮箱都待持有人配置。配置完成前，不要把任何猜测的 GitHub 地址写成官方入口。安全报告见 [SECURITY.md](SECURITY.md)。

本地开发仍使用现有提交说明风格：`feat(模块): 描述`、`fix(模块): 描述`、`docs(模块): 描述`。一次改动对应一个范围清楚的提交。

## 准备工作

固定 SDK、依赖获取、测试、调试构建和发行脚本见 [开发指南](docs/DEVELOPMENT.md)。工具链声明见 [toolchain.json](matrixflow-native/toolchain.json)。产品事实和文档地图见 [README.md](README.md) 与 [文档索引](docs/README.md)。

提交前确认 diff 里没有 API 密钥、keystore、口令、真实任务备份或含密钥的 JSON。测试使用无密钥合成数据。

## 改动边界

- 业务只在 Store 或服务里实现一次。Android 与 Windows 的差异放在适配层。
- 新的设置字段要同时落到 Flutter 模型、Store 的默认值、加载和导入白名单、设置页，以及 en/zh/ja 文案。冻结的 React 字典不用跟着改。
- 新的任务字段按现有 v1 读取、v2 导出契约演进。v2 到 v1 的降级是有损的，见 [备份格式](docs/BACKUP_FORMAT.md)。
- WP10、WP29 和界面实验继续暂停。未实施的托管账号、云同步和界面重绘不要写进功能说明。
- 公共交接、变更记录和实施计划由集成时统一更新。一个子批次不要改写其他批次正在使用的同一批公共文档。

## 验收

代码改动在 `matrixflow-native/` 运行固定 SDK 的 `flutter test --no-pub` 和 `flutter analyze --no-pub`。只改文档时，核对相对链接和文档中的命令是否与脚本、`package.json` 或 workflow 一致。

Android 调试包与 Windows 调试构建按 [开发指南](docs/DEVELOPMENT.md) 执行。正式 Android 包在缺少签名材料时必须失败。没有设备或没有 remote 时，把未测项写清楚，不要把本地调试构建写成稳定发行。
