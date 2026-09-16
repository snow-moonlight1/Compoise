/// Data models mirroring the web app's types.ts (ExportData-compatible).
library;

import 'dart:math';
import 'dart:ui' show Locale;
import 'quadrant.dart';

export 'dart:ui' show Locale;
export 'quadrant.dart';

final _idRandom = Random.secure();
int _idSequence = 0;
String newId() =>
    'mf-${DateTime.now().microsecondsSinceEpoch}-${_idSequence++}-${_idRandom.nextInt(0x7fffffff)}';

String _requiredId(dynamic value) {
  if (value is! String || value.trim().isEmpty) {
    throw const FormatException('Missing record id');
  }
  return value;
}

int? _timestamp(dynamic value) {
  if (value == null) return null;
  if (value is! num || !value.isFinite || value.abs() > 8640000000000000) {
    throw const FormatException('Invalid timestamp');
  }
  return value.toInt();
}

enum AIProtocol { openai, openaiResponses, anthropic }

class AIProtocolX {
  static AIProtocol fromString(
    String? s, {
    AIProtocol fallback = AIProtocol.openai,
  }) {
    switch (s) {
      case 'openai':
      case 'custom': // legacy web value
      case 'gemini': // legacy web value, migrated
        return AIProtocol.openai;
      case 'openai-responses':
        return AIProtocol.openaiResponses;
      case 'anthropic':
        return AIProtocol.anthropic;
    }
    return fallback;
  }

  static String toWire(AIProtocol p) {
    switch (p) {
      case AIProtocol.openai:
        return 'openai';
      case AIProtocol.openaiResponses:
        return 'openai-responses';
      case AIProtocol.anthropic:
        return 'anthropic';
    }
  }
}

class Board {
  String id;
  String name;
  int createdAt;
  Board({required this.id, required this.name, required this.createdAt});

  factory Board.fromJson(Map<String, dynamic> j) => Board(
    id: _requiredId(j['id']),
    name: (j['name'] as String?) ?? 'Board',
    createdAt: (j['createdAt'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt,
  };
}

class SubTask {
  String id;
  String title;
  bool completed;
  int? deadline;
  String? notesMarkdown;
  int? reminderAt;
  SubTask({
    required this.id,
    required this.title,
    this.completed = false,
    this.deadline,
    this.notesMarkdown,
    this.reminderAt,
  });

  factory SubTask.fromJson(Map<String, dynamic> j) => SubTask(
    id: _requiredId(j['id']),
    title: (j['title'] as String?) ?? '',
    completed: (j['completed'] as bool?) ?? false,
    deadline: _timestamp(j['deadline']),
    notesMarkdown: j['notesMarkdown'] as String?,
    reminderAt: _timestamp(j['reminderAt']),
  );

  Map<String, dynamic> toJson({int? targetVersion}) {
    final isV1 = targetVersion == 1;
    return {
      'id': id,
      'title': title,
      'completed': completed,
      if (deadline != null) 'deadline': deadline,
      if (!isV1 && notesMarkdown != null && notesMarkdown!.isNotEmpty)
        'notesMarkdown': notesMarkdown,
      if (!isV1 && reminderAt != null) 'reminderAt': reminderAt,
    };
  }
}

enum UrgencyMode { auto, manual }

class Task {
  String id;
  String boardId;
  String title;
  int quadrant; // 1..4
  bool isLongTerm;
  bool completed;
  int createdAt;
  int? deadline;
  List<SubTask> subtasks;
  String? reasoning;
  UrgencyMode urgencyMode;
  String? notesMarkdown;
  int? reminderAt;
  String? reminderTimezone;

  Task({
    required this.id,
    required this.boardId,
    required this.title,
    required this.quadrant,
    this.isLongTerm = false,
    this.completed = false,
    required this.createdAt,
    this.deadline,
    List<SubTask>? subtasks,
    this.reasoning,
    this.urgencyMode = UrgencyMode.auto,
    this.notesMarkdown,
    this.reminderAt,
    this.reminderTimezone,
  }) : subtasks = subtasks ?? [];

  factory Task.fromJson(Map<String, dynamic> j) => Task(
    id: _requiredId(j['id']),
    boardId: (j['boardId'] as String?) ?? '',
    title: (j['title'] as String?) ?? '',
    quadrant: normalizeQuadrant(j['quadrant']),
    isLongTerm: (j['isLongTerm'] as bool?) ?? false,
    completed: (j['completed'] as bool?) ?? false,
    createdAt: (j['createdAt'] as num?)?.toInt() ?? 0,
    deadline: _timestamp(j['deadline']),
    subtasks:
        ((j['subtasks'] as List?) ?? [])
            .cast<Map<String, dynamic>>()
            .map(SubTask.fromJson)
            .toList(),
    reasoning: j['reasoning'] as String?,
    urgencyMode: (j['urgencyMode'] as String?) == 'manual'
        ? UrgencyMode.manual
        : UrgencyMode.auto,
    notesMarkdown: j['notesMarkdown'] as String?,
    reminderAt: _timestamp(j['reminderAt']),
    reminderTimezone: j['reminderTimezone'] as String?,
  );

  Map<String, dynamic> toJson({int? targetVersion}) {
    final isV1 = targetVersion == 1;
    return {
      'id': id,
      'boardId': boardId,
      'title': title,
      'quadrant': quadrant,
      'isLongTerm': isLongTerm,
      'completed': completed,
      'createdAt': createdAt,
      if (deadline != null) 'deadline': deadline,
      'subtasks':
          subtasks.map((s) => s.toJson(targetVersion: targetVersion)).toList(),
      if (reasoning != null) 'reasoning': reasoning,
      if (!isV1) 'urgencyMode': urgencyMode.name,
      if (!isV1 && notesMarkdown != null && notesMarkdown!.isNotEmpty)
        'notesMarkdown': notesMarkdown,
      if (!isV1 && reminderAt != null) 'reminderAt': reminderAt,
      if (!isV1 && reminderTimezone != null && reminderTimezone!.isNotEmpty)
        'reminderTimezone': reminderTimezone,
    };
  }

  bool get hasSubtasks => subtasks.isNotEmpty;
}

class AIAnalysisResult {
  String title;
  int quadrant;
  bool isLongTerm;
  bool isGrouped;
  String? reasoning;
  List<String> subtasks;
  AIAnalysisResult({
    required this.title,
    required this.quadrant,
    this.isLongTerm = false,
    this.isGrouped = false,
    this.reasoning,
    List<String>? subtasks,
  }) : subtasks = subtasks ?? [];

  Task toTask({
    required String id,
    required String boardId,
    required int createdAt,
    int? deadline,
    String? notesMarkdown,
    int? reminderAt,
    String? reminderTimezone,
  }) => Task(
    id: id,
    boardId: boardId,
    title: title,
    quadrant: quadrant,
    isLongTerm: isLongTerm,
    createdAt: createdAt,
    deadline: deadline,
    reasoning: reasoning,
    notesMarkdown: notesMarkdown,
    reminderAt: reminderAt,
    reminderTimezone: reminderTimezone,
    subtasks: subtasks.map((s) => SubTask(id: newId(), title: s)).toList(),
  );
}

class DecomposeResult {
  String originalTitle;
  List<String> subtasks;
  DecomposeResult({required this.originalTitle, required this.subtasks});
}

class AIConfig {
  String provider;
  AIProtocol protocol;
  String baseUrl;
  String apiKey;
  String model;
  bool enableThinking;

  AIConfig({
    this.provider = 'deepseek',
    this.protocol = AIProtocol.openai,
    this.baseUrl = 'https://api.deepseek.com',
    this.apiKey = '',
    this.model = 'deepseek-v4-flash',
    this.enableThinking = false,
  });

  factory AIConfig.fromJson(Map<String, dynamic> j) {
    var base = (j['customBaseUrl'] as String?) ?? '';
    var m = (j['customModel'] as String?) ?? '';
    if (base.isEmpty) {
      base = 'https://api.deepseek.com';
    }
    if (m.isEmpty || m == 'gpt-4o-mini') {
      m = 'deepseek-v4-flash';
    }

    String pId;
    if (j['providerId'] is String && (j['providerId'] as String).isNotEmpty) {
      pId = j['providerId'] as String;
    } else {
      // Legacy configs (prior to WP01-N) migration:
      if (base.contains('volces.com')) {
        pId = 'volcengine';
      } else if (base.contains('dashscope') || base.contains('aliyun')) {
        pId = 'bailian';
      } else if (base.contains('deepseek.com') || base.isEmpty) {
        pId = 'deepseek';
      } else {
        pId = 'custom';
      }
    }

    return AIConfig(
      provider: pId,
      protocol: AIProtocolX.fromString(
        (j['protocol'] ?? j['provider']) as String?,
      ),
      baseUrl: base,
      apiKey: (j['customApiKey'] as String?) ?? '',
      model: m,
      enableThinking: (j['enableThinking'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'provider': AIProtocolX.toWire(protocol),
    'providerId': provider,
    'protocol': AIProtocolX.toWire(protocol),
    'customBaseUrl': baseUrl,
    'customApiKey': apiKey,
    'customModel': model,
    'enableThinking': enableThinking,
  };
}

enum Language { en, zh, ja }

/// Resolves the preferred [Language] from a prioritized list of device [locales].
/// Matches 'zh', 'ja', and 'en' in order of system priority. Subtags like
/// 'zh-CN', 'zh-TW', and 'zh-HK' map to [Language.zh].
/// If no supported language matches or [locales] is null/empty, returns [Language.en].
Language resolveDeviceLanguage(Iterable<Locale>? locales) {
  if (locales == null) return Language.en;
  for (final loc in locales) {
    final code = loc.languageCode.toLowerCase().replaceAll('-', '_');
    final primary = code.split('_').first;
    if (primary == 'zh') {
      return Language.zh;
    }
    if (primary == 'ja') {
      return Language.ja;
    }
    if (primary == 'en') {
      return Language.en;
    }
  }
  return Language.en;
}

enum ThemeModePref { system, light, dark }

enum ThemeColor { blue, purple, green, orange, pink }

enum InputModePref { single, brainDump }

enum ViewMode { grid, list }

enum FontSizePref { small, standard, large }

enum FontFamilyPref { system, sansSerif, serif, monospace }

class AppSettings {
  Language language;
  ThemeModePref theme;
  ThemeColor themeColor;
  InputModePref defaultInputMode;
  ViewMode viewMode;
  FontSizePref fontSize;
  FontFamilyPref fontFamily;
  bool autoGroupAI;
  bool autoDecomposeAI;
  bool autoCompleteParent;
  bool suppressGroupPrompt;
  bool suppressLongTermPrompt;
  bool hideCompleted;
  int urgencyThresholdDays;
  bool closeToTray;
  String globalShortcut;
  AppSettings({
    this.language = Language.en,
    this.theme = ThemeModePref.system,
    this.themeColor = ThemeColor.blue,
    this.defaultInputMode = InputModePref.single,
    this.viewMode = ViewMode.grid,
    this.fontSize = FontSizePref.standard,
    this.fontFamily = FontFamilyPref.system,
    this.autoGroupAI = false,
    this.autoDecomposeAI = false,
    this.autoCompleteParent = false,
    this.suppressGroupPrompt = false,
    this.suppressLongTermPrompt = false,
    this.hideCompleted = false,
    this.urgencyThresholdDays = 3,
    this.closeToTray = false,
    this.globalShortcut = 'Ctrl+Alt+M',
  });

  factory AppSettings.fromJson(
    Map<String, dynamic> j, {
    Language defaultLanguage = Language.en,
  }) => AppSettings(
    language: Language.values.firstWhere(
      (v) => v.name == (j['language'] as String?),
      orElse: () => defaultLanguage,
    ),
    theme: ThemeModePref.values.firstWhere(
      (v) => v.name == (j['theme'] as String?),
      orElse: () => ThemeModePref.system,
    ),
    themeColor: ThemeColor.values.firstWhere(
      (v) => v.name == (j['themeColor'] as String?),
      orElse: () => ThemeColor.blue,
    ),
    defaultInputMode: InputModePref.values.firstWhere(
      (v) => v.name == (j['defaultInputMode'] as String?),
      orElse: () => InputModePref.single,
    ),
    viewMode: ViewMode.values.firstWhere(
      (v) => v.name == (j['viewMode'] as String?),
      orElse: () => ViewMode.grid,
    ),
    fontSize: FontSizePref.values.firstWhere(
      (v) => v.name == (j['fontSize'] as String?),
      orElse: () => FontSizePref.standard,
    ),
    fontFamily: FontFamilyPref.values.firstWhere(
      (v) => v.name == (j['fontFamily'] as String?),
      orElse: () => FontFamilyPref.system,
    ),
    autoGroupAI: (j['autoGroupAI'] as bool?) ?? false,
    autoDecomposeAI: (j['autoDecomposeAI'] as bool?) ?? false,
    autoCompleteParent: (j['autoCompleteParent'] as bool?) ?? false,
    suppressGroupPrompt: (j['suppressGroupPrompt'] as bool?) ?? false,
    suppressLongTermPrompt: (j['suppressLongTermPrompt'] as bool?) ?? false,
    hideCompleted: (j['hideCompleted'] as bool?) ?? false,
    urgencyThresholdDays: ((j['urgencyThresholdDays'] as num?)?.toInt() ?? 3)
        .clamp(1, 14),
    closeToTray: (j['closeToTray'] as bool?) ?? false,
    globalShortcut: (j['globalShortcut'] as String?) ?? 'Ctrl+Alt+M',
  );

  Map<String, dynamic> toJson({int? targetVersion}) {
    final isV1 = targetVersion == 1;
    return {
      'language': language.name,
      'theme': theme.name,
      'themeColor': themeColor.name,
      'defaultInputMode': defaultInputMode.name,
      if (!isV1) 'viewMode': viewMode.name,
      if (!isV1) 'fontSize': fontSize.name,
      if (!isV1) 'fontFamily': fontFamily.name,
      'autoGroupAI': autoGroupAI,
      'autoDecomposeAI': autoDecomposeAI,
      'autoCompleteParent': autoCompleteParent,
      'suppressGroupPrompt': suppressGroupPrompt,
      'suppressLongTermPrompt': suppressLongTermPrompt,
      'hideCompleted': hideCompleted,
      'urgencyThresholdDays': urgencyThresholdDays,
      if (!isV1) 'closeToTray': closeToTray,
      if (!isV1) 'globalShortcut': globalShortcut,
    };
  }
}

class ExportData {
  static const currentVersion = 2;
  static const legacyVersion = 1;
  static const version = currentVersion;
  static const supportedVersions = {1, 2};

  final int versionNumber;
  final int timestamp;
  final List<Board> boards;
  final List<Task> tasks;
  final AppSettings settings;
  final AIConfig aiConfig;

  ExportData({
    int? version,
    int? timestamp,
    required this.boards,
    required this.tasks,
    required this.settings,
    required this.aiConfig,
  })  : versionNumber = version ?? currentVersion,
        timestamp = timestamp ?? DateTime.now().millisecondsSinceEpoch;

  factory ExportData.fromJson(Map<String, dynamic> j) {
    final v = (j['version'] as num?)?.toInt() ?? legacyVersion;
    if (!supportedVersions.contains(v)) {
      throw FormatException('Unsupported export version: $v');
    }
    return ExportData(
      version: v,
      timestamp: (j['timestamp'] as num?)?.toInt(),
      boards: ((j['boards'] as List?) ?? [])
          .cast<Map<String, dynamic>>()
          .map(Board.fromJson)
          .toList(),
      tasks: ((j['tasks'] as List?) ?? [])
          .cast<Map<String, dynamic>>()
          .map(Task.fromJson)
          .toList(),
      settings: j['settings'] != null && j['settings'] is Map<String, dynamic>
          ? AppSettings.fromJson(j['settings'] as Map<String, dynamic>)
          : AppSettings(),
      aiConfig: j['aiConfig'] != null && j['aiConfig'] is Map<String, dynamic>
          ? AIConfig.fromJson(j['aiConfig'] as Map<String, dynamic>)
          : AIConfig(),
    );
  }

  Map<String, dynamic> toJson({int? targetVersion}) {
    final v = targetVersion ?? versionNumber;
    return {
      'version': v,
      'timestamp': timestamp,
      'boards': boards.map((b) => b.toJson()).toList(),
      'tasks': tasks.map((t) => t.toJson(targetVersion: v)).toList(),
      'settings': settings.toJson(targetVersion: v),
      'aiConfig': aiConfig.toJson(),
    };
  }
}
