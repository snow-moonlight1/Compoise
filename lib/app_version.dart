/// The version this build reports in Settings, diagnostics and the update
/// check. Keep it in step with `version:` in pubspec.yaml; the release process
/// bumps both together and test/app_version_test.dart fails if they drift.
const appVersion = '1.0.0';
const appBuildNumber = 1;

String get appVersionLabel => '$appVersion+$appBuildNumber';
