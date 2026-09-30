import '../storage.dart';

int _sourceVersion(ImportPlan plan) =>
    (plan.payload?['version'] as num?)?.toInt() ?? 1;

bool _ignoredLegacySchedule(ImportPlan plan) =>
    _sourceVersion(plan) < 3 &&
    (plan.payload?.containsKey('scheduleItems') ?? false);

String backupImportResultNotice(Map<String, String> t, ImportPlan plan) =>
    _sourceVersion(plan) < 3
    ? '\n${t['importScheduleLegacyRestoredNone']}'
    : '';

String backupImportVersionDescription(Map<String, String> t, ImportPlan plan) {
  final version = _sourceVersion(plan);
  return [
    t['backupImportVersion']!.replaceAll('{version}', '$version'),
    t[version == 3 ? 'backupImportV3' : 'backupImportLegacy']!,
    if (version < 3 &&
        plan.mode == 'overwrite' &&
        plan.removedScheduleItems > 0)
      t['importScheduleLegacyOverwrite']!.replaceAll(
        '{n}',
        '${plan.removedScheduleItems}',
      ),
    if (_ignoredLegacySchedule(plan)) t['importScheduleLegacyIgnored']!,
  ].join('\n');
}

String backupImportSummary(Map<String, String> t, ImportPlan plan) =>
    '${t['importAddedBoards']}: ${plan.addedBoards}\n'
    '${t['importAddedTasks']}: ${plan.addedTasks}\n'
    '${t['importScheduleAdded']}: ${plan.addedScheduleItems}\n'
    '${t['importScheduleSkipped']}: ${plan.skippedScheduleItems}\n'
    '${t['importScheduleConflicts']}: ${plan.conflictingScheduleItems}\n'
    '${t['importScheduleRemoved']}: ${plan.removedScheduleItems}\n'
    '${t['importSkipped']}: ${plan.skipped}\n'
    '${t['importConflicts']}: ${plan.conflicts}\n'
    '${t['importRepaired']}: ${plan.repaired}\n'
    '${t['importWarnings']}: ${plan.warnings.length}\n'
    '${t['importRemovedBoards']}: ${plan.removedBoards}\n'
    '${t['importRemovedTasks']}: ${plan.removedTasks}\n'
    '${t['importSettingsImpact']}: ${plan.settings == null ? t['importAbsent'] : t['importPresent']}\n'
    '${t['importConfigImpact']}: ${plan.aiConfig == null ? t['importAbsent'] : t['importPresent']}';

/// Translate trusted error categories, never the payload or an exception's
/// interpolated values. B1's untyped format errors stay behind this UI adapter.
String backupImportFormatError(Map<String, String> t, FormatException error) {
  if (error is UnsupportedDataVersionException ||
      error.message.startsWith('Invalid version type in payload')) {
    return t['backupUnsupportedVersion']!;
  }
  const scheduleErrors = {
    'Missing or invalid scheduleItems array',
    'Invalid schedule record',
    'Schedule title exceeds the byte limit',
    'Duplicate schedule id',
    'Missing parent task',
    'Missing event board',
    'Schedule parent task could not be imported',
  };
  if (scheduleErrors.contains(error.message)) {
    return t['importScheduleInvalid']!;
  }
  return error.message.startsWith('Conflicting')
      ? t['importConflictBlocked']!
      : t['importError']!;
}

String backupImportWarningDetails(Map<String, String> t, ImportPlan plan) {
  String warningText(String warning) {
    if (warning == 'Empty backup') return t['importWarningEmpty']!;
    if (warning == 'Orphan task skipped') return t['importWarningOrphan']!;
    if (warning == 'Default board created') return t['importWarningBoard']!;
    if (warning == 'Empty board reference repaired') {
      return t['importWarningReference']!;
    }
    if (warning.startsWith('Successfully migrated legacy')) {
      return t['importWarningLegacy']!;
    }
    if (warning.endsWith('normalized')) {
      return t['importWarningNormalized']!;
    }
    return t['importWarningUnknown']!;
  }

  // The legacy schedule warning is always in the version description above,
  // even when many unrelated warnings fill the details' eight-line budget.
  return plan.warnings
      .where(
        (warning) => !warning.startsWith('Unknown legacy field scheduleItems'),
      )
      .map(warningText)
      .toSet()
      .take(8)
      .join('\n');
}
