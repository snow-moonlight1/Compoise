<p align="center">
  <img src="assets/branding/rounded_rectangle_logo.png" alt="方寸 · Compoise app icon" width="132" />
</p>

<h1 align="center">方寸 · Compoise</h1>

<p align="center"><strong>Sort out what matters, one square at a time.</strong></p>

<p align="center"><a href="README.md">简体中文</a> · English</p>

<p align="center">
  <a href="LICENSE"><img alt="License: GPL-3.0-only" src="https://img.shields.io/badge/License-GPL--3.0--only-3b82f6?style=for-the-badge" /></a>
  <img alt="Flutter" src="https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white" />
  <img alt="Dart" src="https://img.shields.io/badge/Dart-0175C2?style=for-the-badge&logo=dart&logoColor=white" />
  <img alt="Android" src="https://img.shields.io/badge/Android-3DDC84?style=for-the-badge&logo=android&logoColor=white" />
  <img alt="Windows" src="https://img.shields.io/badge/Windows-0078D6?style=for-the-badge&logo=windows&logoColor=white" />
  <img alt="Linux preview" src="https://img.shields.io/badge/Linux-preview-FCC624?style=for-the-badge&logo=linux&logoColor=black" />
</p>

Compoise (方寸) is a local-first task manager for Android, Windows and Linux. It is built around the Eisenhower matrix. It helps you sort tasks by priority and plan your day, and it can use your own AI provider to organize and break down tasks.

## Features

| Feature | What it does |
| --- | --- |
| Matrix and focus | Sort tasks by importance and urgency. Switch between the overview and a single quadrant. |
| Boards | Keep work, study and personal plans apart. |
| Tasks and steps | Break big tasks into steps. Add notes, tags, deadlines and reminders. |
| Today | Gathers the tasks on today's schedule and the ones due today or overdue. |
| Schedule | Day and week views. Book time blocks for tasks or add standalone events. |
| Dynamic urgency | Moves tasks to urgent as their deadline approaches, based on a threshold you set. No AI needed. |
| AI | Bring your own API key to classify, group or break down tasks. |
| Screenshot import | Pick screenshots of a to-do list. The text is recognized on the device, and you review it before importing. The recognition models download on first use. |
| Search and review | Search tasks and notes, filter them, and look back at completed tasks. |
| Appearance | 简体中文, English and 日本語. Theme colors, font size, reduced motion, and optional comic outline and neumorphic styles. |
| Desktop | Keyboard shortcuts, mouse drag and drop, and context menus. On Windows there is also a tray icon and a global hotkey. |
| Backup | Export and import JSON files to move your data between devices. |

## Download

Get the latest version from the [Releases](https://github.com/snow-moonlight1/Compoise/releases) page:

| Platform | Files |
| --- | --- |
| Android | `compoise-<version>-android-arm64-v8a.apk` (most phones), `…-armeabi-v7a.apk` (older 32-bit phones), `…-universal.apk` (all architectures) |
| Windows x64 | `compoise-<version>-windows-x64-setup.exe` (installer) or `…-windows-x64-portable.zip` (portable, just unzip) |
| Linux x64 | `compoise-<version>-linux-amd64.deb`, `…-linux-x86_64.rpm` or `…-linux-x86_64.AppImage` |

`SHA256SUMS.txt` lists the checksums of all files.

**Windows SmartScreen.** The app is not code-signed yet, so Windows may show "Windows protected your PC" on first launch. If the file came from this repository's Releases page, click **More info** and then **Run anyway**.

**Windows data.** Tasks and settings are stored in `%APPDATA%\Compoise\Compoise\`. The API key is stored in the same folder, encrypted by the system. The portable folder itself holds no data, so to upgrade you simply replace it. To remove all data after uninstalling, delete `%APPDATA%\Compoise`.

**Linux dependencies.** DEB and RPM install their dependencies automatically. For the AppImage, install them yourself:

```sh
sudo apt install libgtk-3-0 libsecret-1-0 libayatana-appindicator3-1 zenity fonts-noto-cjk libfuse2
```

- On newer Debian and Ubuntu, `libfuse2` is called `libfuse2t64`.
- Saving an API key needs an unlocked keyring, such as GNOME Keyring or KWallet. Without one, your tasks are still saved, but AI is unavailable.
- The Linux version does not yet show reminder notifications on time, and it has no tray icon or global hotkey.

## AI and privacy

- AI is bring-your-own-key. Pick a provider preset, or enter the address, model and key of any compatible service. Three protocols are supported: OpenAI Compatible, OpenAI Responses and Anthropic Messages.
- Task text is sent to your provider only when you classify, group or break down tasks, and the provider bills you for it. There is no Compoise relay server.
- Tasks, boards and settings stay on your device. There is no account and no automatic cloud sync.
- The API key is kept in the system's secure storage. Backups leave it out by default. If you choose to include it, the key is stored in the backup file as plain text.
- Screenshot recognition runs entirely on your device. Images are never uploaded.

See the [privacy notice](docs/privacy-policy.md).

## Build from source

### Requirements

- Flutter **3.32.8** stable (Dart 3.8.1). The version is pinned in `toolchain.json` and `.flutter-version`, and CI checks it.
- Android: Android SDK and JDK 17.
- Windows: Visual Studio 2022 with "Desktop development with C++".
- Linux: `clang cmake ninja-build pkg-config libgtk-3-dev libsecret-1-dev libayatana-appindicator3-dev`.

### Run

```sh
flutter pub get
flutter run -d <device-id>   # see flutter devices, e.g. windows, linux or a phone
```

### OCR native library

Screenshot import uses a C++ library in `native/ocr/`, built on ncnn and PP-OCRv5. The app runs fine without it; the import screen then says recognition is unavailable.

- The models are not shipped in the packages. On first use, the app downloads them from this repository's `ocr-models-v1` release and checks them against pinned SHA-256 hashes.
- To build the library, prepare ncnn first. See the [development guide](docs/development.md#ocr-原生库).

The [development guide](docs/development.md) also covers checks, tests, release builds and Android signing. It is written in Chinese.

## Project layout

```text
lib/                 Flutter app: UI, data model and logic
  screens/           pages
  widgets/           reusable widgets
  planner/           schedule page
  import_preview/    screenshot import review page
  screenshot_import/ screenshot recognition flow
  ocr/               OCR library binding and model download
  services/          reminders, desktop shell and other platform services
  experiments/       experiments not wired into the app
native/ocr/          OCR native library (C++, ncnn + PP-OCRv5)
android/ windows/ linux/   platform projects
test/                unit and widget tests
integration_test/    integration tests
scripts/ tool/       build, release and diagnostic scripts
docs/                project documentation (mostly Chinese)
legacy/web/          early web prototype, frozen, for reference only
```

See the [architecture overview](docs/architecture.md) for how the parts fit together.

## Contributing

Bug reports, ideas, translations and code are all welcome. Please read the [contributing guide](CONTRIBUTING.md) and the [code of conduct](CODE_OF_CONDUCT.md) first. Report security issues privately, as described in the [security policy](SECURITY.md).

- [Documentation index](docs/README.md)
- [Changelog](CHANGELOG.md)
- [Roadmap](docs/roadmap.md)

## License

© 2026 Compoise contributors. Licensed under the [GNU General Public License v3.0 only](LICENSE). Third-party dependencies and assets keep their own licenses; see the [third-party notices](assets/licenses/THIRD_PARTY_NOTICES.txt). The Material Icons font bundled with Flutter 3.32.8 is credited under CC BY 4.0, with the full text in [MaterialIcons_LICENSE.txt](assets/licenses/MaterialIcons_LICENSE.txt). OCR third-party licenses are listed in [native/ocr/THIRD_PARTY_OCR_NOTICES.md](native/ocr/THIRD_PARTY_OCR_NOTICES.md).
