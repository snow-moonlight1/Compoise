import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

enum AppLogLevel { info, warning, error }

class AppLogEntry {
  const AppLogEntry(this.at, this.level, this.tag, this.message);

  final DateTime at;
  final AppLogLevel level;
  final String tag;

  /// Already redacted and shortened.
  final String message;

  String format() {
    final mark = switch (level) {
      AppLogLevel.info => 'I',
      AppLogLevel.warning => 'W',
      AppLogLevel.error => 'E',
    };
    return '${at.toIso8601String()} $mark [$tag] $message';
  }
}

/// A small local log for diagnosing problems after the fact.
///
/// Entries stay in memory; once [enableFileSink] runs they are also appended
/// to a few rotating files in the app support folder. Nothing leaves the
/// device unless the user exports diagnostics and shares the file. Every
/// message is redacted and shortened before it is kept, and logging never
/// throws.
class AppLog {
  AppLog({this.maxFileBytes = defaultMaxFileBytes});

  static final AppLog instance = AppLog();

  static const maxEntries = 300;
  static const maxMessageChars = 200;
  static const maxStackFrames = 4;
  static const defaultMaxFileBytes = 256 * 1024;
  static const maxFiles = 3;
  static const fileName = 'compoise.log';

  /// Size at which the current file rotates.
  final int maxFileBytes;

  final _entries = ListQueue<AppLogEntry>();
  Directory? _directory;
  int? _currentBytes;
  Future<void> _pending = Future<void>.value();

  List<AppLogEntry> get entries => List.unmodifiable(_entries);
  Directory? get directory => _directory;

  /// Logs to the console in debug builds and keeps a redacted copy.
  static void warn(String tag, String message) {
    debugPrint(message);
    instance.add(AppLogLevel.warning, tag, message);
  }

  static void info(String tag, String message) {
    instance.add(AppLogLevel.info, tag, message);
  }

  void add(AppLogLevel level, String tag, String message) {
    try {
      final entry = AppLogEntry(
        DateTime.now(),
        level,
        tag,
        shortenLogText(redactLogText(message)),
      );
      _keep(entry);
    } catch (_) {}
  }

  /// Records the error type, its redacted message and the top stack frames.
  void error(String tag, Object error, [StackTrace? stack]) {
    try {
      final text = '$error';
      final type = '${error.runtimeType}';
      final head = text.startsWith(type) ? text : '$type: $text';
      final frames = (stack?.toString() ?? '')
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .take(maxStackFrames)
          .map((line) => '\n    ${shortenLogText(redactLogText(line))}')
          .join();
      _keep(
        AppLogEntry(
          DateTime.now(),
          AppLogLevel.error,
          tag,
          '${shortenLogText(redactLogText(head))}$frames',
        ),
      );
    } catch (_) {}
  }

  void _keep(AppLogEntry entry) {
    _entries.addLast(entry);
    while (_entries.length > maxEntries) {
      _entries.removeFirst();
    }
    if (_directory != null) _enqueue(entry.format());
  }

  /// Starts writing to `<app support>/logs`. Entries logged before this call
  /// are written first. Failure leaves the log in memory only.
  Future<void> enableFileSink({Directory? directory}) async {
    if (_directory != null) return;
    try {
      final dir =
          directory ??
          Directory(
            '${(await getApplicationSupportDirectory()).path}'
            '${Platform.pathSeparator}logs',
          );
      await dir.create(recursive: true);
      _directory = dir;
      final earlier = _entries.map((e) => e.format()).join('\n');
      if (earlier.isNotEmpty) _enqueue(earlier);
    } catch (_) {
      _directory = null;
    }
  }

  void _enqueue(String text) {
    final dir = _directory;
    if (dir == null) return;
    _pending = _pending
        .then((_) => _append(dir, '$text\n'))
        .catchError((Object _) {});
  }

  File _file(Directory dir, int index) => File(
    '${dir.path}${Platform.pathSeparator}'
    '${index == 0 ? fileName : 'compoise.$index.log'}',
  );

  Future<void> _append(Directory dir, String text) async {
    final current = _file(dir, 0);
    var size = _currentBytes ??= await current.exists()
        ? await current.length()
        : 0;
    if (size > 0 && size + text.length > maxFileBytes) {
      await _rotate(dir);
      size = 0;
    }
    await current.writeAsString(text, mode: FileMode.append);
    _currentBytes = size + text.length;
  }

  Future<void> _rotate(Directory dir) async {
    final oldest = _file(dir, maxFiles - 1);
    if (await oldest.exists()) await oldest.delete();
    for (var i = maxFiles - 2; i >= 0; i--) {
      final file = _file(dir, i);
      if (await file.exists()) await file.rename(_file(dir, i + 1).path);
    }
  }

  /// The newest part of the log, oldest line first, at most [maxChars].
  Future<String> readRecent({int maxChars = 64 * 1024}) async {
    final dir = _directory;
    if (dir != null) {
      try {
        await _pending;
        final parts = <String>[];
        for (var i = maxFiles - 1; i >= 0; i--) {
          final file = _file(dir, i);
          if (await file.exists()) parts.add(await file.readAsString());
        }
        final text = parts.join();
        if (text.isNotEmpty) return _tail(text, maxChars);
      } catch (_) {}
    }
    return _tail(_entries.map((e) => e.format()).join('\n'), maxChars);
  }

  static String _tail(String text, int maxChars) {
    if (text.length <= maxChars) return text;
    final cut = text.substring(text.length - maxChars);
    final newline = cut.indexOf('\n');
    return newline < 0 ? cut : cut.substring(newline + 1);
  }

  @visibleForTesting
  Future<void> debugReset() async {
    await _pending;
    _entries.clear();
    _directory = null;
  }
}

/// Sends uncaught framework and platform errors to [AppLog] as well.
///
/// Only installs when nobody else owns the handlers yet, so a test binding
/// that watches `FlutterError.onError` keeps its own.
void installAppErrorLogging() {
  if (FlutterError.onError != FlutterError.presentError) return;
  FlutterError.onError = (details) {
    AppLog.instance.error('flutter', details.exception, details.stack);
    FlutterError.presentError(details);
  };
  final dispatcher = WidgetsBinding.instance.platformDispatcher;
  final previous = dispatcher.onError;
  dispatcher.onError = (error, stack) {
    AppLog.instance.error('platform', error, stack);
    return previous?.call(error, stack) ?? false;
  };
}

final _redactions = <(RegExp, String)>[
  (RegExp(r'Bearer\s+[^\s,;]+', caseSensitive: false), 'Bearer <redacted>'),
  (
    RegExp(
      r'((?:api[_-]?key|access[_-]?token|token|secret|password|authorization|x-api-key|key)'
      r'''["']?\s*[:=]\s*["']?)[^\s"',;&}]+''',
      caseSensitive: false,
    ),
    r'$1<redacted>',
  ),
  (RegExp(r'https?://[^\s"<>]+', caseSensitive: false), '<url>'),
  (RegExp(r'[\w.+-]+@[\w-]+(?:\.[\w-]+)+'), '<email>'),
  (RegExp(r'\b(?:sk|pk|rk|ak)-[A-Za-z0-9_\-]{8,}'), '<redacted-key>'),
  (RegExp(r'\bAIza[0-9A-Za-z_\-]{20,}'), '<redacted-key>'),
  // Long runs that mix letters and digits look like keys or tokens; long
  // plain words such as package names stay readable.
  (
    RegExp(r'(?=[A-Za-z_\-]*\d)(?=[0-9_\-]*[A-Za-z])[A-Za-z0-9_\-]{32,}'),
    '<redacted-token>',
  ),
  (RegExp(r'([A-Za-z]:\\Users\\)[^\\\s]+', caseSensitive: false), r'$1<user>'),
  (RegExp(r'(/(?:home|Users)/)[^/\s]+'), r'$1<user>'),
];

/// Removes credentials, addresses, e-mail addresses and user names from a log
/// line. Errors from HTTP clients can carry a full request URL; those collapse
/// to `<url>` so a custom endpoint or a key in a query string never lands in
/// a file the user might share.
String redactLogText(String text) {
  var out = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  for (final (pattern, replacement) in _redactions) {
    out = out.replaceAllMapped(pattern, (m) {
      return replacement.replaceAllMapped(
        RegExp(r'\$(\d)'),
        (g) => m.group(int.parse(g.group(1)!)) ?? '',
      );
    });
  }
  return out;
}

String shortenLogText(String text, [int max = AppLog.maxMessageChars]) =>
    text.length <= max ? text : '${text.substring(0, max - 1)}…';
