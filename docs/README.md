# 文档索引

给接下来阅读仓库的人用。当前客户端是 Flutter Android 与 Windows，源码在 `matrixflow-native/`。公开托管地址尚未配置。

## 先读

| 文档 | 用途 |
|---|---|
| [根 README](../README.md) | 源码、测试构建、稳定发行三个状态，以及数据与 AI 的短说明 |
| [Flutter 客户端说明](../matrixflow-native/README.md) | `matrixflow-native/` 的目录和命令 |
| [开发指南](DEVELOPMENT.md) | 固定 SDK、测试、调试构建、发行脚本和冻结旧版命令 |
| [架构](ARCHITECTURE.md) | 当前存储、凭据、AI 请求和各 OS 包已经落地的结构 |
| [参与说明](../CONTRIBUTING.md) | 本地提交方式；Issue 与 Pull Request 地址待配置 |
| [安全政策](../SECURITY.md) | 安全报告渠道待配置；密钥、明文备份和端点行为 |
| [交接](HANDOFF.md) | 文件顶部是当前集成状态，其余段落是历史交接 |
| [OS27 文档记录](OS27_DOCS_NOTES.md) | 本批文档改了什么、依据是什么、还有哪些待补 |
| [OS26 发行记录](OS26_NOTES.md) | 签名、remote、许可证扫描和持有人尚未决定的事项 |
| [工具链声明](../matrixflow-native/toolchain.json) | Flutter 3.32.8 / Dart 3.8.1 的修订号与本机路径 |
| [MIT 许可证](../LICENSE) | 源码许可 |

## 数据与 AI

| 文档 | 用途 |
|---|---|
| [备份格式](BACKUP_FORMAT.md) | ExportData v1/v2、密钥省略与显式明文、导入上限 |
| [数据兼容](DATA_COMPATIBILITY.md) | 本地键名和版本演进的配套说明；与备份契约不一致时以备份格式页首的当前密钥契约为准 |
| [AI 服务商预设](AI_PROVIDER_PRESETS.md) | DeepSeek、火山引擎、百炼与自定义端点 |
| [Android 包名](ANDROID_PACKAGE_MIGRATION.md) | `com.matrixflow.app` 与更早包名是两个应用；最终包名待持有人决定 |
| [提醒设计](REMINDERS_DESIGN.md) | 设计说明。已落地的重试与权限行为见架构里的 OS12、OS17 小节 |

## 发行计划

[发行规划](RELEASE_PLAN.md) 记录目标渠道和依赖许可证。它不是已经发布的公告。其中 Material Icons 一行已经按固定 SDK 写成 CC-BY 4.0。第 3 节的流程图仍画着本地缺少证书时回退 debug 签名；当前 `scripts/build_release.ps1` 在正式 Android 打包时会拒绝，不以那张图为准。

[2026-09-22 开源准备计划](IMPLEMENTATION_PLAN_2026-09-22_OPEN_SOURCE_READINESS.md) 的文首状态说明 OS01–OS26 已集成。计划后部保留的启动提示词是历史派单。

## 历史材料

这些文件保留原样。它们里面的进度、测试数字或联系地址不能当作当前入口。

| 文档 | 阅读时注意 |
|---|---|
| [变更记录](CHANGELOG.md) | 只追加、不改写的历史。OS27 文档子批次没有往里面加条目 |
| [2026-09-08 实施计划](IMPLEMENTATION_PLAN_2026-09-08.md) | 早期工作包。WP10 继续暂停 |
| [UX 返修计划](IMPLEMENTATION_PLAN_2026-09-17_UX_REWORK.md) | UX01–07 的历史计划。原 UX08 收口并入 OS27 |
| [Flutter 主线决策](ADR_FLUTTER_PRIMARY_2026-09-09.md) | 2026-09-09 起 Flutter 成为唯一持续开发客户端 |
| [2026-09-22 全库审查](FLUTTER_REVIEW_2026-09-22.md) | F24 是本批文档要面对的差异。文中的测试数字是审查当时的数字 |
| [隐私政策](PRIVACY_POLICY.md) | 仍写着密钥明文存放在 SharedPreferences，并链接了本仓库不存在的 GitHub 地址。当前行为以架构和安全政策为准 |
| [商店文案](STORE_LISTING.md) | 隐私政策链接指向同一未配置地址。没有商店上架记录 |
| [v1.0.0 发行说明](release_notes/v1.0.0.md) | 标题写成了已经首发，并保留了已删除的命令台和绝对隐私表述。稳定发行尚未开始 |
| [OS15 记录](OS15_NOTES.md)、[OS23 记录](OS23_NOTES.md)、[OS25 记录](OS25_NOTES.md) | 各包验收记录，不替代 HANDOFF 顶部。同目录还有 OS16–OS22 与 OS26 记录。没有 `OS24_NOTES.md` |

OS24 的工具链结论在 [toolchain.json](../matrixflow-native/toolchain.json) 和 [开发指南](DEVELOPMENT.md)。
