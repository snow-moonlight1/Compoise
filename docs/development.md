# 开发指南

本文说明怎样搭建环境、检查与测试、在各平台构建，以及怎样编译 OCR 原生库。提交流程见[贡献指南](../CONTRIBUTING.md)。

## 环境要求

- Flutter **3.32.8** stable（Dart 3.8.1）。版本固定在 `toolchain.json` 和 `.flutter-version`；CI 用 `scripts/verify_flutter_version.js` 检查实际版本。
- Android：Android SDK、JDK 17。
- Windows：Windows 10/11，Visual Studio 2022 的“使用 C++ 的桌面开发”。
- Linux（以 Debian/Ubuntu 为例）：

  ```sh
  sudo apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev \
    libsecret-1-dev libayatana-appindicator3-dev zenity
  ```

  保存 API 密钥需要可用并已解锁的 Secret Service 密钥环（例如 GNOME Keyring）。没有密钥环时，任务照常保存，只是 AI 不可用。

如果所在网络访问 pub.dev 不稳定，可以按 [Flutter 中国镜像说明](https://docs.flutter.dev/community/china)设置 `PUB_HOSTED_URL` 和 `FLUTTER_STORAGE_BASE_URL`。

## 检查、测试和运行

```sh
flutter pub get
flutter analyze
flutter test
flutter run -d <设备 ID>          # flutter devices 列出可用设备
```

- `flutter test` 运行 `test/` 下的全部单元测试和组件测试，CI 在每个 PR 上运行同样的命令。
- 集成测试：`flutter test integration_test/app_test.dart -d linux`（或 `-d windows`）。
- 需要真机、原生 OCR 库或额外数据的测试默认会跳过，测试文件开头写有开启方式。
- 测试只使用合成数据。截图类测试的数据放在 `test/fixtures/`。

## 构建

```sh
flutter build apk --release        # Android
flutter build windows --release    # Windows
flutter build linux --release      # Linux
```

正式安装包由 CI 构建，见[发布流程](release-process.md)。

### Android 签名

- 正式包必须使用发布证书签名，构建脚本会拒绝用调试签名打正式包。
- 本地构建时，把 `android/key.properties.example` 复制为 `android/key.properties` 并填入签名信息，或者设置 `ANDROID_KEYSTORE_PATH`、`ANDROID_STORE_PASSWORD` 等环境变量（变量名见 `android/app/build.gradle.kts`）。
- keystore 和口令不得提交到仓库。
- CI 从仓库 secret 中读取签名材料，并核对证书的 SHA-256 指纹。

发版后不要更换包名 `com.compoise.app` 或发布证书，否则 Android 会把新版本当成另一个应用，无法覆盖升级。

### 应用图标

图标源文件是 `assets/branding/CompoiseLogo.png`。修改后运行：

```powershell
powershell -ExecutionPolicy Bypass -File tool/generate_brand_icons.ps1
```

## OCR 原生库

截图识别使用 `native/ocr/` 下的 C++ 库 `compoise_ocr`，它基于 [ncnn](https://github.com/Tencent/ncnn) 和 PP-OCRv5 mobile 模型，Dart 通过 FFI 调用它（`lib/ocr/ocr_runtime.dart`）。

- **不编译这个库也能开发其他功能**，截图识别入口会提示暂不可用。
- **模型不随安装包分发。** 应用第一次识别时，从本仓库的 `ocr-models-v1` Release 下载模型，按 `lib/ocr/ocr_model_download.dart` 中固定的 SHA-256 校验，然后保存到应用数据目录。

编译步骤（与 CI 相同）：

1. 构建固定版本的 ncnn（版本写在 `third_party/ncnn_pin.txt`），并下载校验过的 `stb_image.h`：

   ```sh
   scripts/ci/build_ncnn.sh linux-x64 "$HOME/ncnn"   # 或 windows-x64、android-arm64-v8a 等
   ```

2. 让平台工程找到它们：
   - **Linux / Windows**：设置环境变量，然后正常运行 `flutter build`，库会被放进 bundle。

     ```sh
     export WP17_OCR_NCNN_DIR="$HOME/ncnn/install/lib/cmake/ncnn"
     export WP17_OCR_STB_DIR="$HOME/ncnn/third_party"
     flutter build linux --release
     ```

   - **Android**：在 `android/local.properties` 中加入下面两行。`wp17OcrNcnnRoot` 目录下需要有每个 ABI 的 `ncnn-android-<abi>/install`。

     ```properties
     wp17OcrNcnnRoot=/path/to/ncnn
     wp17OcrStbDir=/path/to/ncnn/third_party
     ```

识别规则和隐私边界见[截图识别导入](ocr.md)，第三方许可见 `native/ocr/THIRD_PARTY_OCR_NOTICES.md`。

## 数据与隐私

- 不要提交真实的任务备份、API 密钥、签名材料、日志或本机配置。
- 默认的 JSON 备份不含 API 密钥。用户明确选择包含时，文件里的密钥是明文。
