# Changelog

All notable changes to this project are recorded here. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

本文件记录每个版本的主要变化，格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循[语义化版本](https://semver.org/lang/zh-CN/)。

## [Unreleased]

## [1.0.0] - 2026-10-13

First public release. 首个公开版本。

### Added

- Eisenhower matrix with an overview and a single-quadrant focus mode, multiple boards, tasks with steps, notes, tags, deadlines and reminders.
- Dynamic urgency: tasks move to the urgent side as their deadline approaches, based on a threshold you set.
- Today page that groups tasks by planned day, including the ones carried over.
- Schedule page with day and week views, time blocks for tasks and standalone events, time-zone aware.
- AI with your own API key: classify, group and break down tasks. Presets for DeepSeek, Volcengine and Alibaba Bailian, and custom endpoints using the OpenAI Compatible, OpenAI Responses or Anthropic Messages protocol. A single "Test connection" button.
- Screenshot import: on-device OCR with ncnn and PP-OCRv5, and a review page before anything is saved. The native library ships in the packages; the models download on first use and are checked against SHA-256.
- JSON backup export and import, including multi-file backups for large libraries. The API key is left out unless you choose to include it.
- Search, filters and a completed-tasks view.
- 简体中文, English and 日本語; theme colors, font size, reduced motion, and optional comic outline and neumorphic styles.
- Desktop: keyboard shortcuts, mouse drag and drop, context menus and a resizable task pool. Windows also gets a tray icon, a global hotkey and close to tray.
- Release packages:
  - Android: arm64-v8a, armeabi-v7a and universal APKs.
  - Windows x64: installer and portable ZIP.
  - Linux x64: DEB, RPM and AppImage.

### Known limitations

- Windows builds are not code-signed, so SmartScreen may warn on first launch.
- The Linux version does not deliver scheduled reminder notifications, and it has no tray icon or global hotkey.
- Windows ARM64 is not built yet.

[Unreleased]: https://github.com/snow-moonlight1/Compoise/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/snow-moonlight1/Compoise/releases/tag/v1.0.0
