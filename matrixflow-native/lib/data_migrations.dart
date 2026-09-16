/// Data migration engine and payload validation gates for MatrixFlow export/import.
library;

import 'models.dart';

/// Thrown when importing an export payload with an unsupported or unknown future version.
class UnsupportedDataVersionException extends FormatException {
  final int version;
  UnsupportedDataVersionException(this.version)
      : super(
          'Unsupported export payload version: $version. '
          'Please update MatrixFlow to import this file.',
        );
}

/// Thrown when an import payload contains unrecoverable structural corruption.
class CorruptDataPayloadException extends FormatException {
  CorruptDataPayloadException(super.message);
}

/// Result of parsing, validating, and migrating an export payload.
class MigrationResult {
  final int sourceVersion;
  final int targetVersion;
  final List<Board> boards;
  final List<Task> tasks;
  final AppSettings? settings;
  final AIConfig? aiConfig;
  final List<String> warnings;

  MigrationResult({
    required this.sourceVersion,
    required this.targetVersion,
    required this.boards,
    required this.tasks,
    this.settings,
    this.aiConfig,
    this.warnings = const [],
  });
}

/// Migrator and validator ensuring backward compatibility and strict safety gates.
class DataMigrator {
  static const int currentVersion = ExportData.currentVersion;
  static const int legacyVersion = ExportData.legacyVersion;
  static const Set<int> supportedVersions = ExportData.supportedVersions;

  /// Pure functional validation and migration of an export JSON map.
  ///
  /// Does NOT mutate any global store or runtime state.
  /// Throws [UnsupportedDataVersionException] if `version` > [currentVersion] or not supported.
  /// Throws [FormatException] if top-level structural requirements (boards, tasks) are not met.
  static MigrationResult migratePayload(Map<String, dynamic> json) {
    // 1. Version gate check
    int sourceVersion = legacyVersion;
    if (json.containsKey('version')) {
      final rawVersion = json['version'];
      if (rawVersion is! num || rawVersion.toInt() != rawVersion) {
        throw FormatException('Invalid version type in payload: $rawVersion');
      }
      final v = rawVersion.toInt();
      if (!supportedVersions.contains(v)) {
        throw UnsupportedDataVersionException(v);
      }
      sourceVersion = v;
    }

    // 2. Structural validation
    if (json['boards'] is! List) {
      throw const FormatException('Missing or invalid "boards" list in payload');
    }
    if (json['tasks'] is! List) {
      throw const FormatException('Missing or invalid "tasks" list in payload');
    }

    final warnings = <String>[];

    // 3. Parse and deduplicate boards
    final rawBoards = json['boards'] as List;
    final parsedBoards = <Board>[];
    final seenBoardIds = <String>{};
    for (final raw in rawBoards) {
      if (raw is! Map<String, dynamic>) {
        warnings.add('Skipped non-map board entry');
        continue;
      }
      try {
        final board = Board.fromJson(raw);
        if (seenBoardIds.add(board.id)) {
          parsedBoards.add(board);
        } else {
          warnings.add('Duplicate board ID removed: ${board.id}');
        }
      } catch (e) {
        warnings.add('Failed to parse board: $e');
      }
    }

    // 4. Parse and deduplicate tasks
    final rawTasks = json['tasks'] as List;
    final parsedTasks = <Task>[];
    final seenTaskIds = <String>{};
    for (final raw in rawTasks) {
      if (raw is! Map<String, dynamic>) {
        warnings.add('Skipped non-map task entry');
        continue;
      }
      try {
        final task = Task.fromJson(raw);
        if (seenTaskIds.add(task.id)) {
          parsedTasks.add(task);
        } else {
          warnings.add('Duplicate task ID removed: ${task.id}');
        }
      } catch (e) {
        warnings.add('Failed to parse task: $e');
      }
    }

    // 5. Parse settings with whitelist and safe defaults
    AppSettings? parsedSettings;
    if (json['settings'] != null) {
      if (json['settings'] is! Map<String, dynamic>) {
        throw const FormatException('Invalid settings format in payload');
      }
      parsedSettings = AppSettings.fromJson(json['settings'] as Map<String, dynamic>);
    }

    // 6. Parse aiConfig with fallback
    AIConfig? parsedConfig;
    if (json['aiConfig'] != null) {
      if (json['aiConfig'] is! Map<String, dynamic>) {
        throw const FormatException('Invalid aiConfig format in payload');
      }
      parsedConfig = AIConfig.fromJson(json['aiConfig'] as Map<String, dynamic>);
    }

    // 7. Version upgrade normalization
    if (sourceVersion == legacyVersion) {
      warnings.add('Successfully migrated legacy v1 payload to v2');
    }

    return MigrationResult(
      sourceVersion: sourceVersion,
      targetVersion: currentVersion,
      boards: parsedBoards,
      tasks: parsedTasks,
      settings: parsedSettings,
      aiConfig: parsedConfig,
      warnings: warnings,
    );
  }
}
