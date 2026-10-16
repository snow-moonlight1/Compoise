import 'package:shared_preferences/shared_preferences.dart';

/// Choices that belong to this device rather than to the task library.
///
/// They live in their own SharedPreferences keys on purpose: backups, the
/// save protocol and import preflight only know the library's settings, so
/// these never travel to another device and an import never touches them.
/// Values are loaded once at startup and then read synchronously.
class DevicePrefs {
  DevicePrefs();

  static final DevicePrefs instance = DevicePrefs();

  static const updateCheckKey = 'compoise-update-check-enabled';
  static const lastUpdateCheckKey = 'compoise-update-last-check';
  static const aiTimeoutKey = 'compoise-ai-timeout-seconds';

  /// How long a sort or split request may wait for the model.
  static const aiTimeoutChoices = <int>[30, 60, 120];
  static const defaultAiTimeoutSeconds = 60;

  bool _updateCheckEnabled = false;
  DateTime? _lastUpdateCheck;
  int _aiTimeoutSeconds = defaultAiTimeoutSeconds;

  /// Off until the user turns it on: the app makes no request by itself.
  bool get updateCheckEnabled => _updateCheckEnabled;
  DateTime? get lastUpdateCheck => _lastUpdateCheck;
  int get aiTimeoutSeconds => _aiTimeoutSeconds;
  Duration get aiTimeout => Duration(seconds: _aiTimeoutSeconds);

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _updateCheckEnabled = prefs.getBool(updateCheckKey) ?? false;
      final last = prefs.getInt(lastUpdateCheckKey);
      _lastUpdateCheck = last == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(last);
      _aiTimeoutSeconds = _validTimeout(prefs.getInt(aiTimeoutKey));
    } catch (_) {
      // A device preference must never block startup; keep the defaults.
    }
  }

  Future<void> setUpdateCheckEnabled(bool value) async {
    _updateCheckEnabled = value;
    await _write((prefs) => prefs.setBool(updateCheckKey, value));
  }

  Future<void> setLastUpdateCheck(DateTime value) async {
    _lastUpdateCheck = value;
    await _write(
      (prefs) => prefs.setInt(lastUpdateCheckKey, value.millisecondsSinceEpoch),
    );
  }

  Future<void> setAiTimeoutSeconds(int seconds) async {
    _aiTimeoutSeconds = _validTimeout(seconds);
    await _write((prefs) => prefs.setInt(aiTimeoutKey, _aiTimeoutSeconds));
  }

  static int _validTimeout(int? seconds) =>
      aiTimeoutChoices.contains(seconds) ? seconds! : defaultAiTimeoutSeconds;

  Future<void> _write(
    Future<bool> Function(SharedPreferences prefs) write,
  ) async {
    try {
      await write(await SharedPreferences.getInstance());
    } catch (_) {
      // The in-memory value still applies for this session.
    }
  }
}
