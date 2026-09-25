# Focus review harness (2026-09-25)

Review-only synthetic comparison; this is not the production entry point.

From the repository root run `./scripts/prepare_focus_review.ps1`. It archives
pre-OS baseline `9d3bbc4` and reviewed HEAD `9e30f01` into a new temporary directory,
then generates `focus_review.dart` from the template. It neither reads local
preferences/credentials nor installs an APK. Build in the printed app directory
with Flutter 3.32.8 after `flutter pub get`:

```powershell
& 'D:/Dev_SDKs/Flutter_3.32.8/bin/flutter.bat' build apk --profile --target focus_review.dart --no-pub
```

The Android ID is **com.matrixflow.review20260925**, label **MatrixFlow Review**.
Keep this ID when installing: never replace, clear or uninstall the user's normal
app for this benchmark. The launch component is
`com.matrixflow.review20260925/com.matrixflow.matrixflow_native.MainActivity`.
Repeat using `--debug` to compare build modes. No production release signing is
required for profile/debug. Do not use this harness as a distributable app.

Output is `FOCUS_REVIEW_META`, 54 `FOCUS_REVIEW_ROW` records, then
`FOCUS_REVIEW_DONE`, or `FOCUS_REVIEW_ERROR`. Collect only this app process's
logcat entries. Each scene warms for 1.5 s; three enter/switch/exit cycles run with
950 ms between changes. Task counts are 3, 100, 3; task 0 has two expanded children.
Both versions run under the same SDK in one process, with synthetic in-memory
preferences, no real credentials and no platform reminders. Reverse order and
repeat cooled-device runs before drawing a comparative conclusion.

Metrics are engine FrameTiming build/raster/total spans, in microseconds, with
per-motion p50/p90/max and frames exceeding the reported display Hz budget in
either build or raster. These counts are **not measured presented FPS**. Validate
thermal state, refresh rate, first-use effects, timing-delivery boundaries and
actual production MatrixScreen/theme/input with DevTools separately. The default
MaterialApp wrapper does not reproduce the entire app or original SDK.

This review built profile/debug harnesses and installed the profile harness after
the phone reconnected. **No valid device rows were collected**. The user then
requested stopping measurement and accepting the production Release build by
visual experience. Further use of this diagnostic is optional, only if Release
still feels janky or the user requests measurement. See the final-repair plan RF01.
