import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Intent to open the in-app command palette.
class OpenCommandPaletteIntent extends Intent {
  const OpenCommandPaletteIntent();
}

/// Intent to trigger new task input.
class NewTaskIntent extends Intent {
  const NewTaskIntent();
}

/// Intent to navigate to search screen.
class SearchTasksIntent extends Intent {
  const SearchTasksIntent();
}

/// Intent to view completed tasks.
class OpenCompletedIntent extends Intent {
  const OpenCompletedIntent();
}

/// Intent to toggle between grid and list view mode.
class ToggleViewModeIntent extends Intent {
  const ToggleViewModeIntent();
}

/// Intent to open settings.
class OpenSettingsIntent extends Intent {
  const OpenSettingsIntent();
}

/// Intent to display keyboard shortcuts help dialog.
class ShortcutsHelpIntent extends Intent {
  const ShortcutsHelpIntent();
}

/// Intent to handle Esc key navigation.
class EscapeIntent extends Intent {
  const EscapeIntent();
}

/// Map of logical keyboard key sets to MatrixFlow intents.
/// Standard shortcuts designed for desktop platforms (Windows / macOS / Linux).
final Map<ShortcutActivator, Intent> matrixShortcuts = {
  // Command palette: Ctrl+K or Cmd+K
  LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyK):
      const OpenCommandPaletteIntent(),
  LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyK):
      const OpenCommandPaletteIntent(),

  // New task: Ctrl+N or Cmd+N
  LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyN):
      const NewTaskIntent(),
  LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyN):
      const NewTaskIntent(),

  // Search tasks: Ctrl+F or Cmd+F
  LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyF):
      const SearchTasksIntent(),
  LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyF):
      const SearchTasksIntent(),

  // Completed tasks: Ctrl+H or Cmd+H
  LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyH):
      const OpenCompletedIntent(),
  LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyH):
      const OpenCompletedIntent(),

  // Toggle view mode: Ctrl+Shift+V or Cmd+Shift+V
  LogicalKeySet(
    LogicalKeyboardKey.control,
    LogicalKeyboardKey.shift,
    LogicalKeyboardKey.keyV,
  ): const ToggleViewModeIntent(),
  LogicalKeySet(
    LogicalKeyboardKey.meta,
    LogicalKeyboardKey.shift,
    LogicalKeyboardKey.keyV,
  ): const ToggleViewModeIntent(),

  // Settings: Ctrl+, or Cmd+,
  LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.comma):
      const OpenSettingsIntent(),
  LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.comma):
      const OpenSettingsIntent(),

  // Shortcuts help: Ctrl+/ or Cmd+/ or F1
  LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.slash):
      const ShortcutsHelpIntent(),
  LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.slash):
      const ShortcutsHelpIntent(),
  LogicalKeySet(LogicalKeyboardKey.f1): const ShortcutsHelpIntent(),

  // Esc
  LogicalKeySet(LogicalKeyboardKey.escape): const EscapeIntent(),
};

/// Displays the Keyboard Shortcuts Help modal dialog.
Future<void> showShortcutsHelpDialog(
  BuildContext context,
  Map<String, String> t,
) {
  final theme = Theme.of(context);
  final isDark = theme.brightness == Brightness.dark;

  final shortcutsList = <Map<String, String>>[
    {
      'keys': 'Ctrl + K',
      'label': t['shortcutCommandPalette'] ?? 'Open Command Palette',
    },
    {
      'keys': 'Ctrl + N',
      'label': t['shortcutNewTask'] ?? 'Create New Task',
    },
    {
      'keys': 'Ctrl + F',
      'label': t['shortcutSearch'] ?? 'Search Tasks',
    },
    {
      'keys': 'Ctrl + H',
      'label': t['shortcutCompleted'] ?? 'View Completed Tasks',
    },
    {
      'keys': 'Ctrl + Shift + V',
      'label': t['shortcutToggleView'] ?? 'Toggle Grid / List View',
    },
    {
      'keys': 'Ctrl + ,',
      'label': t['shortcutSettings'] ?? 'Open Settings',
    },
    {
      'keys': 'Ctrl + / 或 F1',
      'label': t['shortcutHelp'] ?? 'Keyboard Shortcuts Help',
    },
    {
      'keys': 'Esc',
      'label': t['shortcutEsc'] ?? 'Close Modal / Exit Focus / Cancel Selection',
    },
  ];

  return showDialog<void>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: Row(
          children: [
            Icon(Icons.keyboard_outlined, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            Text(t['shortcutsHelp'] ?? 'Keyboard Shortcuts'),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: shortcutsList.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final item = shortcutsList[index];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color:
                            isDark
                                ? theme.colorScheme.surfaceContainerHighest
                                : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color:
                              isDark
                                  ? theme.colorScheme.outlineVariant
                                  : const Color(0xFFCBD5E1),
                        ),
                      ),
                      child: Text(
                        item['keys']!,
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        item['label']!,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(t['close'] ?? 'Close'),
          ),
        ],
      );
    },
  );
}
