import '../models.dart';
import '../schedule_item.dart';
import '../schedule_time.dart';
import '../widgets/schedule_layout.dart';
import 'planner_labels.dart';

/// "1 小时" / "30 分钟" / "1 小时 30 分钟". Never shows seconds or fractions.
String plannerDuration(int startAt, int endAt, Map<String, String> t) {
  final minutes = ((endAt - startAt) / Duration.millisecondsPerMinute).round();
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h > 0 && m > 0) {
    return plannerFilled(t['scheduleDurHM']!, {'h': '$h', 'm': '$m'});
  }
  if (h > 0) return plannerFilled(t['scheduleDurH']!, {'h': '$h'});
  return plannerFilled(t['scheduleDurM']!, {'m': '${m == 0 ? 1 : m}'});
}

/// "10月11日 周日 00:00–01:00" in the display zone. A span over midnight shows
/// both dates.
String plannerRangeLabel(
  ScheduleItem item,
  String zone,
  Language language,
  Map<String, String> t,
) {
  final start = scheduleLocalTime(item.startAt, zone);
  final end = scheduleLocalTime(item.endAt, zone);
  final startDate = ScheduleCivilDate(start.year, start.month, start.day);
  final endDate = ScheduleCivilDate(end.year, end.month, end.day);
  final first = plannerDayTitle(startDate, language, t);
  final a = plannerClock(item.startAt, zone);
  final b = plannerClock(item.endAt, zone);
  if (scheduleDateLabel(startDate) == scheduleDateLabel(endDate)) {
    return '$first $a–$b';
  }
  return '$first $a – ${plannerDayTitle(endDate, language, t)} $b';
}

/// Zero-padded clock such as "09:05" for detail text. The axis keeps "9:00".
String plannerClock(int instant, String zone) {
  final local = scheduleLocalTime(instant, zone);
  return '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

/// Items that share time with [item] (excluding itself).
List<ScheduleItem> plannerConcurrent(
  Iterable<ScheduleItem> all,
  ScheduleItem item,
) => overlappingScheduleItems(all, item);
