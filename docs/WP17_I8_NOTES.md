# WP17-I8：三端可复现的官方 OCR 可选包装

日期：2026-10-03。默认发行仍不含 OCR。本包只增加显式 opt-in 的官方模型候选路线，并用独立 manifest 记录启用状态、来源、库/资源哈希和许可证。没有签名、没有正式发布，也没有打开默认发行开关。

基线 `459f9a28cefdcac9196825b2d4ac70250dbf3b8d`。分支 `codex/wp17-i8`。独立工作树 `D:\Dev_project\martix-wp17-i8`。提交身份 `wp17-i8-agent <wp17-i8-agent@local.invalid>`。仓库本地 `user.name` 仍是其他工作树共用的 `wp17-q2-agent`，本包提交只用本次命令覆盖身份，没有改共享配置。没有 amend、push、tag 或调用其他 Agent。设备、AVD 和真实窗口都没有占用。

Flutter 固定为 `toolchain.json` 的 3.32.8 / Dart 3.8.1。Windows SDK `D:\Dev_SDKs\Flutter_3.32.8`，Linux `/home/ubuntu/develop/flutter`。`pub get --enforce-lockfile` 没有改 `pubspec.lock`。模型锁 `native/ocr/tools/models.lock.json` 的 SHA-256 仍是 `f38320cefe758056f619dc293eb63201c42a7c82f8af506bafbc4dda81551c1d`。

## 入口

缓存、日志、构建镜像和临时目录都在仓库外。官方模式必须同时给出已核验部署和本机 ncnn SDK；默认模式拒绝这两个参数，因此不会下载模型或准备 ncnn。Android 还要显式 SDK 与 JDK。下载只在 `--download` 时发生，并沿用既有 TLS 与哈希检查，失败不回退到别的来源。

```text
python scripts/wp17_i8_models.py --private-root <外部根> [--download] [--convert-python <venv解释器>] [--check]
python native/ocr/tools/i8_prepare_native.py --out <外部新目录> --assets <已核验缓存> --platform windows|linux|x86_64|arm64-v8a (--reuse-sdk | --source | --download)
python scripts/wp17_i8_candidate.py --platform windows|linux|android-x86_64|android-arm64-v8a --mode official|default --private-root <外部根> --flutter <固定 flutter> --pub-cache <根内缓存>
```

桌面资源装到 `data/wp17-ocr/`，Android 装到 `assets/wp17-ocr/`，库按单个 ABI 放入包内。`lib/ocr/ocr_assets.dart` 在 Windows 上和 Linux 一样读取可执行文件旁的这份目录；默认构建没有该目录时仍返回空。CMake 只在 `WP17_OCR_MODELS_DIR` 指向已复核资源时安装模型。Android 的 `wp17I8Unsigned` 只用于本包未签名检查，不能通过正式签名门，也不能和诊断身份同时使用。

普通 R1 规则没有放宽。含 OCR 的 Windows ZIP 仍被 R1 拒绝；该事实写入 `OCR_CANDIDATE.json`，`ordinaryCandidate` 为 false。

## 候选证据

| 候选 | 提交 | 退出 | 结果 |
|---|---|---:|---|
| Windows 官方 | `25f739e9f26e334f7a3f823ff48f6478e5f27c2d` | 0 | `matrixflow_ocr.dll` 14,126,080 字节，`7deb6c7796ee973e`；native12 为 12 图 / 274 行，文字差 0，最大几何差 0。身份 Compoise 1.0.0+1，未签名。R1 拒绝 OCR 残留 |
| Windows 默认 | `ba63fa6f4e6dd6ebfff2b7f14737d62c56c25d65` | 0 | 19 个文件，OCR 残留 0。同一身份，未签名 |
| Linux 官方，复用已复核 ncnn | `84f235d2917bf43115b9a3e7174ce716b702001e` | 0 | `lib/libmatrixflow_ocr.so` 16,940,384 字节；native12 文字差 0，最大几何差 0 |
| Linux 官方，干净源码编译 ncnn | `ba63fa6f4e6dd6ebfff2b7f14737d62c56c25d65` | 0 | 同一 native12 结果。库 SHA-256 `2128f163d485a7c612e7ed00fee18cf68887d47f8c19df2b04c23d19d0939642`。ncnn 提交 `c6b351b56fbe32e0381ae00331e3df649b20d7b7` |
| Linux 默认 | `ba63fa6f4e6dd6ebfff2b7f14737d62c56c25d65` | 0 | 19 个文件，OCR 残留 0 |
| Android x86_64 官方 | `ba63fa6f4e6dd6ebfff2b7f14737d62c56c25d65` | 0 | 单 ABI `lib/x86_64/libmatrixflow_ocr.so` 5,390,184 字节。包名 `com.matrixflow.app`，versionName 1.0.0，未签名 |
| Android arm64-v8a 官方 | `ba63fa6f4e6dd6ebfff2b7f14737d62c56c25d65` | 0 | 单 ABI `lib/arm64-v8a/libmatrixflow_ocr.so` 6,482,256 字节。同一应用身份，未签名 |
| Android x86_64 默认 | `ba63fa6f4e6dd6ebfff2b7f14737d62c56c25d65` | 0 | 443 个条目，OCR 残留 0。同一应用身份，未签名 |

官方包都带 14 项 OCR 路径：五个模型/字典文件、六份许可与 notice、`deployed.json`、`bundle-manifest.json`，以及对应平台的一个 OCR 库。notice 为 6,343 字节，SHA-256 `f54ad9b0c5a4367900c2849e69b374426d3f52f39be7744a36935ee00d17bfe9`，与 `native/ocr/THIRD_PARTY_OCR_NOTICES.md` 一致。全新 Linux 部署根里锁住的 4 个 ncnn 产物、5 份上游许可附件和字典，共 10 个文件，逐一匹配原锁。

`25f739e` 之后的提交只改 Android 打包、转换解释器路径，以及在调用 Flutter 前清除继承的 `GIT_DIR`。Windows 官方构建命令和资源安装规则没有变，所以没有为同一产物重编一次。Linux 干净缓存候选和三端默认检查都在最终实现提交 `ba63fa6f4e6dd6ebfff2b7f14737d62c56c25d65` 上完成。

证明在私有根，不入库：

- Windows / Android：`D:\Dev_project\martix-wp17-i8-private\runs\`
- Linux：`/home/ubuntu/wp17i8-private/runs/`
- 每份目录有 `OCR_CANDIDATE.json`。桌面官方另有 `native12.json`

## 拒绝与构建失败

包装回归 `python native/ocr/tools/i8_test_packaging.py`：12 项通过，退出 0。覆盖缺模型、缺许可、伪造 notice、错误 ABI、默认包 OCR 残留，以及复制失败后保留已安装字节和时间戳。

真实缓存 `D:\Dev_project\martix-wp17-i8-private\faults\results.json`：完整资源退出 0；缺模型、坏摘要、缺许可、坏 notice 均退出 3。空缓存离线准备退出 4，日志为缺少 `ppocrv5_dict.txt`。

构建中的三次失败和修复：

- Windows 证明首次退出 3：主机 PowerShell 没有自动加载签名检查模块。显式导入后重跑退出 0。
- 全新转换首次退出 5：解析 venv 的 Python 符号链接后选中系统解释器。改为保留绝对路径后，下载、校验、转换和部署退出 0，输出匹配原锁。
- Android x86_64 首次编译成功，但检查器把仅大小写不同的 APK 路径当成重复。改为只拒绝完全同名条目后，两个 ABI 都退出 0。

## 默认回归

在工作树、私有 pub 缓存和固定 Flutter 3.32.8 上：

- `flutter pub get --enforce-lockfile --offline` 退出 0，锁文件无差异。
- `flutter analyze --no-pub` 退出 0，No issues found。
- `flutter test --no-pub` 退出 0：1413 项通过，12 项条件跳过。其中一项是当前卷不生成 8.3 短名。跳过不是设备通过。

## 实现提交

本说明之前的实现提交，从基线向前：

- `71b9910615bf6b31dcc2f51e54f3e8e7d5c9dcaa` Add isolated opt-in official OCR candidate packaging
- `42aaf2a95e69b57aa59ad5868bc3183599d6abeb` Verify candidate identities and keep staging temporaries private
- `25f739e9f26e334f7a3f823ff48f6478e5f27c2d` Load host PowerShell verification modules explicitly
- `84f235d2917bf43115b9a3e7174ce716b702001e` Isolate Flutter SDK Git context for WSL builds
- `ddb83a982b35d6f4042f1796cb08384c7e13f78a` Preserve pinned conversion virtual environment interpreter
- `8f4dc4e7e2076c2fe06ad2f9500e9b738449b9e7` Respect APK path case and isolate JVM compiler files
- `ba63fa6f4e6dd6ebfff2b7f14737d62c56c25d65` Normalize private JVM paths in Java properties

## 边界与未验证

改动限于 `scripts/wp17_i8_*`、`native/ocr/tools/i8_*`、`native/ocr/i8_resources.cmake`、两端桌面 CMake 的可选资源安装、`android/app/build.gradle.kts` 的未签名单 ABI 检查，以及 `lib/ocr/ocr_assets.dart` 的 Windows 资源发现。没有改 OCR runtime、主入口、Store、`scripts/release_candidate.py`、`scripts/build_release.ps1` 或发行 workflow。模型、二进制、日志和私有根都没有提交。

未验证：真机、AVD、原生 GUI、正式签名、应用商店和质量门。证明里的 `deviceQualityGate` 为 unverified，`publication` 为未授权。Android 默认缺席只构建了 x86_64；arm64 官方包已单独构建。没有把这些候选称为普通发行候选。
