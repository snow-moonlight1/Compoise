/// Data models mirroring the web app's types.ts (ExportData-compatible).
library;

export 'quadrant.dart';

enum AIProtocol { openai, openaiResponses, anthropic }

class AIProtocolX {
  static AIProtocol fromString(String? s, {AIProtocol fallback = AIProtocol.openai}) {
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
        id: j['id'] as String,
        name: (j['name'] as String?) ?? 'Board',
        createdAt: (j['createdAt'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'createdAt': createdAt};
}

class SubTask {
  String id;
  String title;
  bool completed;
  int? deadline;
  SubTask({required this.id, required this.title, this.completed = false, this.deadline});

  factory SubTask.fromJson(Map<String, dynamic> j) => SubTask(
        id: j['id'] as String,
        title: (j['title'] as String?) ?? '',
        completed: (j['completed'] as bool?) ?? false,
        deadline: (j['deadline'] as num?)?.toInt(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'completed': completed,
        if (deadline != null) 'deadline': deadline,
      };
}

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
  }) : subtasks = subtasks ?? [];

  factory Task.fromJson(Map<String, dynamic> j) => Task(
        id: j['id'] as String,
        boardId: (j['boardId'] as String?) ?? '',
        title: (j['title'] as String?) ?? '',
        quadrant: (j['quadrant'] as num?)?.toInt() ?? 4,
        isLongTerm: (j['isLongTerm'] as bool?) ?? false,
        completed: (j['completed'] as bool?) ?? false,
        createdAt: (j['createdAt'] as num?)?.toInt() ?? 0,
        deadline: (j['deadline'] as num?)?.toInt(),
        subtasks: ((j['subtasks'] as List?) ?? [])
            .whereType<Map<String, dynamic>>()
            .map(SubTask.fromJson)
            .toList(),
        reasoning: j['reasoning'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'boardId': boardId,
        'title': title,
        'quadrant': quadrant,
        'isLongTerm': isLongTerm,
        'completed': completed,
        'createdAt': createdAt,
        if (deadline != null) 'deadline': deadline,
        'subtasks': subtasks.map((s) => s.toJson()).toList(),
        if (reasoning != null) 'reasoning': reasoning,
      };

  bool get hasSubtasks => subtasks.isNotEmpty;
}

class AIAnalysisResult {
  String title;
  int quadrant;
  bool isLongTerm;
  String? reasoning;
  List<String> subtasks;
  AIAnalysisResult({
    required this.title,
    required this.quadrant,
    this.isLongTerm = false,
    this.reasoning,
    List<String>? subtasks,
  }) : subtasks = subtasks ?? [];

  Task toTask({required String id, required String boardId, required int createdAt}) => Task(
        id: id,
        boardId: boardId,
        title: title,
        quadrant: quadrant,
        isLongTerm: isLongTerm,
        createdAt: createdAt,
        reasoning: reasoning,
        subtasks: subtasks
            .map((s) => SubTask(
                  id: '$id-${s.hashCode}',
                  title: s,
                ))
            .toList(),
      );
}

class DecomposeResult {
  String originalTitle;
  List<String> subtasks;
  DecomposeResult({required this.originalTitle, required this.subtasks});
}

class AIConfig {
  AIProtocol protocol;
  String baseUrl;
  String apiKey;
  String model;
  AIConfig({
    this.protocol = AIProtocol.openai,
    this.baseUrl = '',
    this.apiKey = '',
    this.model = 'gpt-4o-mini',
  });

  factory AIConfig.fromJson(Map<String, dynamic> j) => AIConfig(
        protocol: AIProtocolX.fromString(j['provider'] as String?),
        baseUrl: (j['customBaseUrl'] as String?) ?? '',
        apiKey: (j['customApiKey'] as String?) ?? '',
        model: (j['customModel'] as String?) ?? 'gpt-4o-mini',
      );

  Map<String, dynamic> toJson() => {
        'provider': AIProtocolX.toWire(protocol),
        'customBaseUrl': baseUrl,
        'customApiKey': apiKey,
        'customModel': model,
      };
}

enum Language { en, zh, ja }

enum ThemeModePref { system, light, dark }

enum ThemeColor { blue, purple, green, orange, pink }

enum InputModePref { single, brainDump }

class AppSettings {
  Language language;
  ThemeModePref theme;
  ThemeColor themeColor;
  InputModePref defaultInputMode;
  bool autoGroupAI;
  bool autoDecomposeAI;
  bool autoCompleteParent;
  bool suppressGroupPrompt;
  bool suppressLongTermPrompt;
  bool hideCompleted;
  int urgencyThresholdDays;
  AppSettings({
    this.language = Language.en,
    this.theme = ThemeModePref.system,
    this.themeColor = ThemeColor.blue,
    this.defaultInputMode = InputModePref.single,
    this.autoGroupAI = false,
    this.autoDecomposeAI = false,
    this.autoCompleteParent = false,
    this.suppressGroupPrompt = false,
    this.suppressLongTermPrompt = false,
    this.hideCompleted = false,
    this.urgencyThresholdDays = 3,
  });

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        language: Language.values.firstWhere(
          (v) => v.name == (j['language'] as String?),
          orElse: () => Language.en,
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
        autoGroupAI: (j['autoGroupAI'] as bool?) ?? false,
        autoDecomposeAI: (j['autoDecomposeAI'] as bool?) ?? false,
        autoCompleteParent: (j['autoCompleteParent'] as bool?) ?? false,
        suppressGroupPrompt: (j['suppressGroupPrompt'] as bool?) ?? false,
        suppressLongTermPrompt: (j['suppressLongTermPrompt'] as bool?) ?? false,
        hideCompleted: (j['hideCompleted'] as bool?) ?? false,
        urgencyThresholdDays: (j['urgencyThresholdDays'] as num?)?.toInt() ?? 3,
      );

  Map<String, dynamic> toJson() => {
        'language': language.name,
        'theme': theme.name,
        'themeColor': themeColor.name,
        'defaultInputMode': defaultInputMode.name,
        'autoGroupAI': autoGroupAI,
        'autoDecomposeAI': autoDecomposeAI,
        'autoCompleteParent': autoCompleteParent,
        'suppressGroupPrompt': suppressGroupPrompt,
        'suppressLongTermPrompt': suppressLongTermPrompt,
        'hideCompleted': hideCompleted,
        'urgencyThresholdDays': urgencyThresholdDays,
      };
}

class ExportData {
  static const version = 1;
  final List<Board> boards;
  final List<Task> tasks;
  final AppSettings settings;
  final AIConfig aiConfig;
  ExportData({required this.boards, required this.tasks, required this.settings, required this.aiConfig});

  Map<String, dynamic> toJson() => {
        'version': version,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'boards': boards.map((b) => b.toJson()).toList(),
        'tasks': tasks.map((t) => t.toJson()).toList(),
        'settings': settings.toJson(),
        'aiConfig': aiConfig.toJson(),
      };
}
