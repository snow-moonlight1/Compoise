import 'package:shared_preferences/shared_preferences.dart';

/// "Seen once" flags for the planner guide and the quadrant-swipe hint.
///
/// These live in their own SharedPreferences keys on purpose: they are view
/// hints, not library data, so they stay out of backups, the save protocol and
/// the startup-recovery key list.
class PlannerGuideFlags {
  const PlannerGuideFlags._();

  static const guideKey = 'compoise-planner-guide-seen';
  static const tabHintKey = 'compoise-planner-tabhint-seen';

  static Future<bool> seen(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(key) ?? false;
    } catch (_) {
      // A hint must never break the page; assume it was already shown.
      return true;
    }
  }

  static Future<void> mark(String key, [bool value = true]) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (_) {}
  }
}
