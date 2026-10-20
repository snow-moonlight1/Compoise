# 发布流程

正式安装包全部由 GitHub Actions 构建（`.github/workflows/release.yml`）。CI 只会创建**草稿** Release，测试通过后由维护者手动发布。

## 1. 准备版本

1. 在 `pubspec.yaml` 中把 `version` 改成新版本，格式为 `X.Y.Z+N`：`X.Y.Z` 是对外版本号，`N` 是 Android 的 versionCode，每次发版都要加一。
   同时把 `lib/app_version.dart` 里的 `appVersion` 和 `appBuildNumber` 改成一样的值（设置页、诊断信息和检查更新用它）；`test/update_check_test.dart` 会在两者不一致时失败。
2. 在 [CHANGELOG](../CHANGELOG.md) 中把 `Unreleased` 下的内容移到新版本条目 `## [X.Y.Z] - YYYY-MM-DD`，`Unreleased` 留空。条目先写中文小节（`### 新增`、`### 变更`、`### 修复`、`### 维护`、`### 已知限制` 等），再写对应的英文小节（`### Added`、`### Changed`、`### Fixed`、`### Maintenance`、`### Known limitations` 等），每个小节至少一条；文件末尾补上 `[X.Y.Z]` 链接，并把 `[Unreleased]` 链接改成从 `vX.Y.Z` 开始比较。
   这个条目会原样放在 Release 说明顶部（“更新 / What's new”），所以要写全用户能感知的变化和已知限制，不只写主要功能。平时合并用户能看到的改动时就补进 `Unreleased`，发版时只需整理。
   `scripts/changelog_notes.py check` 检查 `pubspec.yaml` 版本对应的条目：有日期、是最新一条、中英文小节都有内容、链接齐全。PR 检查每次都跑它，所以改了版本号却没写条目的 PR 不能合并；打正式标签时还会要求 `Unreleased` 已经清空。
3. 通过 PR 合并到 `main`，确认 CI 是绿的。

## 2. 打标签

在 `main` 的最新提交上打标签并推送：

```sh
git checkout main && git pull
git tag v1.1.0
git push origin v1.1.0
```

标签必须和 `pubspec.yaml` 一致（`v1.1.0` 或 `v1.1.0+2`），否则 CI 会直接失败。以 `-ci.N` 结尾的标签（如 `v1.1.0-ci.1`）用于试跑，会生成草稿预发布，不检查版本号。

正式标签还要通过 `scripts/check_build_number.py`：版本号和 `+N` 构建号都必须大于之前每一个正式 `v*` 标签（不算 `-ci` 标签和当前标签），否则 release 工作流在构建前就停止。这样 Android 不会因为 versionCode 没有增加而无法覆盖安装。本地可以先跑：

```sh
python3 scripts/check_build_number.py --tag v1.1.0
```

## 3. CI 构建

依次运行这些步骤：

1. **preflight**：检查版本号、更新日志条目（`scripts/changelog_notes.py check --tag`）和 Flutter 版本，运行 `flutter analyze` 和 `flutter test`。
2. 三个平台并行构建，每个平台都会先编译 ncnn 和 OCR 原生库：
   - **build-android**：生成 armeabi-v7a、arm64-v8a 和 universal（含 x86_64）三个 APK。用仓库 secret 中的发布证书签名，并核对证书指纹。
   - **build-windows**：生成 x64 便携 ZIP 和 NSIS 安装程序。
   - **build-linux**：生成 x64 的 DEB、RPM 和 AppImage。
3. **publish**：汇总文件，写入 `RELEASE_METADATA.txt` 和 `SHA256SUMS.txt`，生成中英双语的发布说明，创建草稿 Release。发布说明顶部是 CHANGELOG 里这个版本的条目（`scripts/changelog_notes.py notes`），下面是固定的功能介绍和下载指引；`-ci` 标签用同版本的条目或 `Unreleased`，都没有时省略。

产物共 10 个文件：

| 平台 | 文件 |
| --- | --- |
| Android | `compoise-X.Y.Z-android-arm64-v8a.apk`、`…-armeabi-v7a.apk`、`…-universal.apk` |
| Windows | `compoise-X.Y.Z-windows-x64-setup.exe`、`…-windows-x64-portable.zip` |
| Linux | `compoise-X.Y.Z-linux-amd64.deb`、`…-linux-x86_64.rpm`、`…-linux-x86_64.AppImage` |
| 校验 | `SHA256SUMS.txt`、`RELEASE_METADATA.txt` |

OCR 模型不放进安装包，应用第一次识别时从 `ocr-models-v1` Release 下载。CI 会检查安装包里确实没有模型文件。

### 需要的 secret

| Secret | 用途 |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | base64 编码的发布 keystore |
| `ANDROID_STORE_PASSWORD`、`ANDROID_KEY_PASSWORD` | keystore 和密钥的口令 |
| `ANDROID_KEY_ALIAS` | 密钥别名 |
| `ANDROID_RELEASE_CERT_SHA256` | 发布证书的 SHA-256 指纹，CI 用它核对签名 |

缺少任何一项，打标签构建都会失败，CI 不会产出调试签名的正式包。

## 4. 测试草稿

在草稿 Release 中下载安装包，在每个平台上至少检查以下几项：

- **安装和启动**：全新安装后能看到引导页、默认任务板和空的四象限，三种语言都能切换。
- **升级**：在上一个版本里建几条测试数据（父子任务、截止日期、提醒、笔记），再覆盖安装新版本，确认数据都在。Android 必须用同一证书签名，才能覆盖安装。
- **备份往返**：导出 JSON，清除数据后再导入，核对任务板、任务、子项、日程和设置。
- **截图识别**：模型能下载，中文截图能识别，校对页里的文字显示完整。
- **外观**：默认、漫画描边、拟态三种风格下，主要页面都没有文字被裁切。

用 `sha256sum -c --strict SHA256SUMS.txt` 校验文件（Windows 上用 `Get-FileHash`）。

有问题就删除草稿和标签，修复后重新打标签：

```sh
gh release delete v1.1.0 --yes     # 或者在网页上删除草稿
git push origin :refs/tags/v1.1.0
git tag -d v1.1.0
```

## 5. 发布

确认无误后，在 GitHub 网页上编辑草稿 Release，点击 **Publish release**。

## 平台说明

- **Android**：包名 `com.compoise.app`。发版后不要再改包名或发布证书，否则无法覆盖升级。
- **Windows**：安装包和程序都没有 Authenticode 代码签名，首次运行时 SmartScreen 可能会提示，发布说明里要写明这一点。数据目录由 exe 的 `CompanyName` 和 `ProductName` 决定，即 `%APPDATA%\Compoise\Compoise`。改动这两个字段就等于换了数据目录，发版后不要改。
- **Linux**：DEB 和 RPM 会自动安装依赖。AppImage 需要用户自己安装依赖和 `libfuse2`。

## 本地预检

`scripts/build_release.ps1` 可以在本地检查版本、标签和签名的前置条件，也可以打 Windows 便携包。Windows PowerShell 和 Linux 上的 `pwsh` 都能运行：

```powershell
pwsh -File scripts/build_release.ps1 -Platform All -ExpectedTag vX.Y.Z+N -ValidateOnly
```

## 许可

所有发行文件都以 GPL-3.0-only 发布。`RELEASE_METADATA.txt` 中记录了 `license=GPL-3.0-only`，第三方许可见 `assets/licenses/` 和 `native/ocr/THIRD_PARTY_OCR_NOTICES.md`。
