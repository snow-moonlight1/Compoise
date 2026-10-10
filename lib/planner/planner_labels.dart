import '../models.dart';
import '../schedule_time.dart';

const _englishMonths = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Day title such as "Oct 6 Tue" or "10月6日 周二". The chevron is a separate icon.
String plannerDayTitle(
  ScheduleCivilDate date,
  Language language,
  Map<String, String> t,
) {
  final weekday =
      t['scheduleWeekday${DateTime.utc(date.year, date.month, date.day).weekday}']!;
  if (language == Language.en) {
    return '${_englishMonths[date.month - 1]} ${date.day} $weekday';
  }
  return '${date.month}月${date.day}日 $weekday';
}

/// Week title such as "Sep 28–Oct 4" or "10月5日–11日".
String plannerWeekTitle(
  ScheduleCivilDate start,
  ScheduleCivilDate end,
  Language language,
) {
  if (language == Language.en) {
    final left = '${_englishMonths[start.month - 1]} ${start.day}';
    final right = start.month == end.month
        ? '${end.day}'
        : '${_englishMonths[end.month - 1]} ${end.day}';
    return '$left–$right';
  }
  if (start.month == end.month) {
    return '${start.month}月${start.day}日–${end.day}日';
  }
  return '${start.month}月${start.day}日–${end.month}月${end.day}日';
}

String plannerCounted(String template, int count) =>
    template.replaceAll('{n}', '$count');

/// Date-strip mark. Chinese drops the 周 prefix; English and Japanese stay.
String plannerWeekdayMark(
  Map<String, String> t,
  Language language,
  int weekday,
) {
  final raw = t['scheduleWeekday$weekday']!;
  if (language == Language.zh && raw.startsWith('周') && raw.length > 1) {
    return raw.substring(1);
  }
  return raw;
}

/// ISO week of [date]. Week 1 is the week that contains the first Thursday.
int plannerIsoWeek(ScheduleCivilDate date) {
  final utc = DateTime.utc(date.year, date.month, date.day);
  final thursday = utc.add(Duration(days: DateTime.thursday - utc.weekday));
  final firstThursday = DateTime.utc(thursday.year, 1, 4);
  final week1Monday = firstThursday.subtract(
    Duration(days: firstThursday.weekday - DateTime.monday),
  );
  final monday = thursday.subtract(const Duration(days: 3));
  return monday.difference(week1Monday).inDays ~/ 7 + 1;
}

String plannerFilled(String template, Map<String, String> values) {
  var result = template;
  for (final entry in values.entries) {
    result = result.replaceAll('{${entry.key}}', entry.value);
  }
  return result;
}

String plannerWeekSummary(
  String template,
  int count,
  double hours,
  Map<String, String> t,
) {
  final duration = hours == hours.roundToDouble()
      ? '${hours.toStringAsFixed(0)} ${t['scheduleHours']}'
      : '${hours.toStringAsFixed(1)} ${t['scheduleHours']}';
  return template.replaceAll('{n}', '$count').replaceAll('{duration}', duration);
}
