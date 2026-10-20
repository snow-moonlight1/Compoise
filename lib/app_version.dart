/// The version this build reports in Settings, diagnostics and the update
/// check. Keep it in step with `version:` in pubspec.yaml; the release process
/// bumps both together and test/update_check_test.dart fails if they drift.
const appVersion = '1.2.0';
const appBuildNumber = 4;

String get appVersionLabel => '$appVersion+$appBuildNumber';
