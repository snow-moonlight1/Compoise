# 贡献指南 / Contributing

感谢你愿意帮助改进方寸 · Compoise！本文说明怎样搭建环境、提交改动和发布版本。

*Thanks for helping improve Compoise! In short: fork the repo, branch off `main`, and keep each change small. Run `flutter analyze` and `flutter test`, then open a pull request. Update all three languages (en, zh, ja) in `lib/l10n.dart` for any text users see. The rest of this guide is in Chinese.*

## 行为准则

参与本项目即表示你同意遵守[行为准则](CODE_OF_CONDUCT.md)。安全问题请按[安全策略](SECURITY.md)私下报告，不要开公开 Issue。

## 报告问题和建议

- 先搜索现有 Issue，避免重复。
- 请使用 Issue 模板，写清平台和版本、复现步骤、预期结果和实际结果。
- 不要附上 API 密钥、真实备份或个人日志，截图里也只用虚构数据。

## 搭建开发环境

1. 安装 Flutter **3.32.8** stable（Dart 3.8.1）。版本固定在 `toolchain.json` 和 `.flutter-version` 中，CI 会检查。
2. 按目标平台安装依赖，见 [README](README.md#从源码构建)和[开发指南](docs/development.md)。
3. 在仓库根目录运行：

   ```sh
   flutter pub get
   flutter run -d <设备 ID>
   ```

截图识别需要 OCR 原生库。不编译这个库，也不影响其他功能的开发，详见[开发指南](docs/development.md#ocr-原生库)。

## 分支和 Pull Request

1. 从最新的 `main` 拉一个分支，按类型命名：`fix/…`、`feat/…`、`docs/…`、`ci/…`、`chore/…`。
2. 每个 PR 只做一件事。重构和功能改动请分开提交。
3. 提交前在本地运行：

   ```sh
   flutter analyze
   flutter test
   ```

   如果改了平台工程，请在对应平台上构建并手动试一遍。
4. 按 PR 模板写清改了什么、为什么改、怎样验证，以及哪些平台没有测过。
5. CI（`.github/workflows/pr.yml`）通过、并经维护者审阅后合并。

### 提交信息

用一行英文祈使句概括改动，可以加类型前缀，例如：

```text
fix(linux): save window bounds on live resize
ci(release): bilingual release notes
Center neumorphic labelled fields on the review page
```

需要说明原因时，空一行后在正文里写。

## 代码约定

- **业务逻辑**放在 `Store` 和 `lib/` 下的服务里，页面只负责展示和交互。平台差异放在平台服务里，不要在页面里到处判断平台。
- **手机和桌面**的交互分开处理。改一端时不要顺带改变另一端的行为，也不要改默认主题。规则集中在 `lib/ui/platform_ui_policy.dart`。
- **文案**写在 `lib/l10n.dart`，English、简体中文和日本語三种语言必须一起更新。文案面向普通用户：成功时简短或不提示；失败时用一句话说清原因和下一步怎么做。不要出现状态码、内部格式版本号和开发者术语，也不要写防御性的免责说明。详见[设计规范](docs/design-guidelines.md)。
- **主题**：默认、漫画描边和拟态三种风格下都要检查，特别注意拟态主题下文字有没有被裁切。
- **测试**：用描述行为的名字，例如 `screenshot_status_bar_test.dart`；测试里只用合成数据。
- **数据格式**：改动本地数据或备份格式时，同步更新 [备份格式](docs/backup-format.md)和[本地存储](docs/local-storage.md)，并补充往返测试。
- **依赖**：新增依赖或素材前，确认它的许可证与 GPL-3.0-only 兼容，并在 PR 里说明来源。
- **更新日志**：用户能看到的改动（新功能、行为变化、修复、新的限制），在 [CHANGELOG](CHANGELOG.md) 的 `Unreleased` 下各补一条中文和英文。

## 发布版本

维护者负责发版，流程详见[发布流程](docs/release-process.md)：

1. 把 `pubspec.yaml` 的 `version` 改成新版本（如 `1.1.0+2`），并在 [CHANGELOG](CHANGELOG.md) 里把 `Unreleased` 整理成这个版本的条目（先中文、后英文），然后合并到 `main`。这个条目就是 Release 说明顶部的“更新 / What's new”，没有它 CI 会拒绝。
2. 在 `main` 上打标签并推送：

   ```sh
   git tag v1.1.0
   git push origin v1.1.0
   ```

3. `release.yml` 会构建 Android、Windows 和 Linux 的安装包，并创建一个**草稿** Release。
4. 在各平台装上草稿里的安装包测试，没有问题后再手动发布。

## 安全与隐私

不要提交 API 密钥、Android 发布签名、keystore、带密钥的备份或真实用户数据。签名配置参考 `android/key.properties.example`，真实配置只放在本机被 Git 忽略的文件里，或放在 CI secret 中。

## 许可

提交贡献即表示你同意按 GPL-3.0-only 发布你的代码。
