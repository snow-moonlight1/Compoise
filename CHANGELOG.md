# Changelog

All notable changes to this project are recorded here. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

本文件记录每个版本的主要变化，格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循[语义化版本](https://semver.org/lang/zh-CN/)。

## [Unreleased]

## [1.1.0] - 2026-10-19

### Added

- Optional task count progress: a finite target or unlimited counting, a separate Record once action, automatic completion at the target, and Undo.
- Android text sharing into a manual multiline preview, plus New task / Today launcher shortcuts; shares wait while an existing draft is open.
- Linux reminders while the app runs, a deduplicated missed-reminder summary, system tray and close to tray, and opt-in XDG login startup.
- Backup format v4 preserves count progress; v1/v2/v3 imports remain supported and exports to older formats refuse to drop counters.

### Changed

- Windows global quick capture now opens the new-task input after restoring the window.
- Calendar recurrence is deferred; count progress does not create calendar events or change task dates.


## [1.0.1] - 2026-10-19

### Added

- Settings → Help & About: an optional daily update check (off by default; it only asks GitHub for the latest release), a "Check for updates" button and the app version.
- "Export diagnostics" saves a text file with the version, system details and recent errors for bug reports. Keys, addresses, e-mail addresses and task content are left out.
- AI wait time (30, 60 or 120 seconds) for sorting and splitting tasks. Connection tests keep their own 30-second limit.

### Changed

- Sorting and splitting tasks now wait up to 60 seconds by default instead of 30, and the timeout message points to the new setting.
- Reminder and Windows tray failures are also kept in a small local log (memory, plus a few rotating files in the app data folder), with secrets removed.

### Maintenance

- Formal releases are refused when their version or build number is not greater than every earlier release.
- Documentation brought in line with 1.0.0: the Today page, notices, Android reminder setup, privacy notice and test names.

## [1.0.0] - 2026-10-15

First public release. 首个公开版本。

### Added

- Eisenhower matrix with an overview and a single-quadrant focus mode, multiple boards, tasks with steps, notes, tags, deadlines and reminders.
- Dynamic urgency: tasks move to the urgent side as their deadline approaches, based on a threshold you set.
- Today page that gathers the tasks scheduled for today and the ones due today or overdue; ticking one off strikes it through before it leaves.
- Schedule page with day and week views, time blocks for tasks and standalone events, time-zone aware.
- "Deadline & reminder" dialog that saves an exact date and time for tasks, steps, new tasks and AI input.
- Android reminder setup after the tutorial, which can be skipped: asks in turn for notifications, exact alarms and background running, links to the vendor autostart page, and reads Xiaomi / HyperOS autostart status. It can be reopened from Settings.
- AI with your own API key: classify, group and break down tasks; a breakdown fills the open draft. Presets for DeepSeek, Volcengine and Alibaba Bailian, and custom endpoints using the OpenAI Compatible, OpenAI Responses or Anthropic Messages protocol. A single "Test connection" button.
- Screenshot import (PNG and JPG): on-device OCR with ncnn and PP-OCRv5. Recognized tasks start selected on a review list where you can edit, deselect, split or merge them before saving. The native library ships in the packages; the models download on first use and are checked against SHA-256.
- JSON backup export and import, including multi-file backups for large libraries. The API key is left out unless you choose to include it.
- Search, filters and a completed-tasks view.
- Multi-select: drag the selected tasks together onto another quadrant (long press on phones, mouse drag on desktop).
- Quiet notices: routine successes show nothing; the remaining notices appear one at a time and close after about 4 seconds. Deleting by swipe offers Undo.
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

[Unreleased]: https://github.com/snow-moonlight1/Compoise/compare/v1.1.0...HEAD
[1.0.1]: https://github.com/snow-moonlight1/Compoise/releases/tag/v1.0.1
[1.0.0]: https://github.com/snow-moonlight1/Compoise/releases/tag/v1.0.0

[1.1.0]: https://github.com/snow-moonlight1/Compoise/releases/tag/v1.1.0
