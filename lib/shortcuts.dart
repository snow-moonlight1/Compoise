import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

/// One help row generated from the same table as [matrixShortcuts].
class ShortcutHelpItem {
  final String keys;
  final String labelKey;
  final String fallbackLabel;

  const ShortcutHelpItem({
    required this.keys,
    required this.labelKey,
    required this.fallbackLabel,
  });
}

/// Windows help labels. Ctrl only; never mix in ⌘.
const List<ShortcutHelpItem> shortcutHelpItems = [
  ShortcutHelpItem(
    keys: 'Ctrl + N',
    labelKey: 'shortcutNewTask',
    fallbackLabel: 'Create New Task',
  ),
  ShortcutHelpItem(
    keys: 'Ctrl + F',
    labelKey: 'shortcutSearch',
    fallbackLabel: 'Search Tasks',
  ),
  ShortcutHelpItem(
    keys: 'Ctrl + H',
    labelKey: 'shortcutCompleted',
    fallbackLabel: 'View Completed Tasks',
  ),
  ShortcutHelpItem(
    keys: 'Ctrl + Shift + L',
    labelKey: 'shortcutToggleView',
    fallbackLabel: 'Toggle Grid / List View',
  ),
  ShortcutHelpItem(
    keys: 'Ctrl + ,',
    labelKey: 'shortcutSettings',
    fallbackLabel: 'Open Settings',
  ),
  ShortcutHelpItem(
    keys: 'Ctrl + / or F1',
    labelKey: 'shortcutHelp',
    fallbackLabel: 'Keyboard Shortcuts Help',
  ),
  ShortcutHelpItem(
    keys: 'Esc',
    labelKey: 'shortcutEsc',
    fallbackLabel: 'Close Modal / Exit Focus / Cancel Selection',
  ),
];

/// Map of logical keyboard key sets to Compoise intents.
/// Toggle view uses Ctrl+Shift+L so Ctrl+Shift+V never hijacks paste.
final Map<ShortcutActivator, Intent> matrixShortcuts = {
  LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyN):
      const NewTaskIntent(),
  LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyN):
      const NewTaskIntent(),
  LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyF):
      const SearchTasksIntent(),
  LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyF):
      const SearchTasksIntent(),
  LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyH):
      const OpenCompletedIntent(),
  LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyH):
      const OpenCompletedIntent(),
  LogicalKeySet(
    LogicalKeyboardKey.control,
    LogicalKeyboardKey.shift,
    LogicalKeyboardKey.keyL,
  ): const ToggleViewModeIntent(),
  LogicalKeySet(
    LogicalKeyboardKey.meta,
    LogicalKeyboardKey.shift,
    LogicalKeyboardKey.keyL,
  ): const ToggleViewModeIntent(),
  LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.comma):
      const OpenSettingsIntent(),
  LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.comma):
      const OpenSettingsIntent(),
  LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.slash):
      const ShortcutsHelpIntent(),
  LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.slash):
      const ShortcutsHelpIntent(),
  LogicalKeySet(LogicalKeyboardKey.f1): const ShortcutsHelpIntent(),
  LogicalKeySet(LogicalKeyboardKey.escape): const EscapeIntent(),
};

/// Lets EditableText keep Ctrl+C/V/A/Z and Ctrl+Shift+V instead of app intents.
class EditingAwareShortcutManager extends ShortcutManager {
  EditingAwareShortcutManager()
    : super(modal: true, shortcuts: matrixShortcuts);

  @override
  KeyEventResult handleKeypress(BuildContext context, KeyEvent event) {
    final focus = FocusManager.instance.primaryFocus;
    final widget = focus?.context?.widget;
    if (widget is EditableText) {
      return KeyEventResult.ignored;
    }
    return super.handleKeypress(context, event);
  }
}

/// Displays the Keyboard Shortcuts Help modal dialog.
Future<void> showShortcutsHelpDialog(
  BuildContext context,
  Map<String, String> t,
) {
  final theme = Theme.of(context);
  final isDark = theme.brightness == Brightness.dark;

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
            itemCount: shortcutHelpItems.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final item = shortcutHelpItems[index];
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
                        color: isDark
                            ? theme.colorScheme.surfaceContainerHighest
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isDark
                              ? theme.colorScheme.outlineVariant
                              : const Color(0xFFCBD5E1),
                        ),
                      ),
                      child: Text(
                        item.keys,
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        t[item.labelKey] ?? item.fallbackLabel,
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
