import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../storage.dart';
import '../theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _baseUrlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _modelController = TextEditingController();
  bool _fileBusy = false;

  @override
  void initState() {
    super.initState();
    final store = context.read<Store>();
    _baseUrlController.text = store.aiConfig.baseUrl;
    _apiKeyController.text = store.aiConfig.apiKey;
    _modelController.text = store.aiConfig.model;
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final t = store.t;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(t['settings']!)),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _sectionTitle(theme, t['language']!, Icons.language),
            SegmentedButton<Language>(
              segments: const [
                ButtonSegment(value: Language.en, label: Text('EN')),
                ButtonSegment(value: Language.zh, label: Text('中文')),
                ButtonSegment(value: Language.ja, label: Text('日本語')),
              ],
              selected: {store.settings.language},
              onSelectionChanged:
                  (s) => store.updateSettings(
                    (settings) => settings..language = s.first,
                  ),
            ),
            const SizedBox(height: 20),

            _sectionTitle(theme, t['theme']!, Icons.brightness_6_outlined),
            Wrap(
              spacing: 8,
              children: [
                for (final mode in ThemeModePref.values)
                  ChoiceChip(
                    label: Text(
                      t[switch (mode) {
                        ThemeModePref.light => 'themeLight',
                        ThemeModePref.dark => 'themeDark',
                        _ => 'themeSystem',
                      }]!,
                    ),
                    selected: store.settings.theme == mode,
                    onSelected:
                        (_) => store.updateSettings(
                          (settings) => settings..theme = mode,
                        ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final color in ThemeColor.values)
                  _ColorDot(
                    color: themeSeedColors[color]!,
                    selected: store.settings.themeColor == color,
                    tooltip:
                        t['color${color.name[0].toUpperCase()}${color.name.substring(1)}']!,
                    onTap:
                        () => store.updateSettings(
                          (settings) => settings..themeColor = color,
                        ),
                  ),
              ],
            ),
            const SizedBox(height: 20),

            _sectionTitle(theme, t['automation']!, Icons.auto_mode_outlined),
            _toggle(
              context,
              t['autoDecomposeAI']!,
              t['autoDecomposeDesc']!,
              store.settings.autoDecomposeAI,
              (v) => store.updateSettings(
                (settings) => settings..autoDecomposeAI = v,
              ),
            ),
            _toggle(
              context,
              t['suppressLongTermPrompt']!,
              null,
              store.settings.suppressLongTermPrompt,
              (v) => store.updateSettings(
                (settings) => settings..suppressLongTermPrompt = v,
              ),
            ),
            _toggle(
              context,
              t['autoGroupAI']!,
              t['autoGroupDesc']!,
              store.settings.autoGroupAI,
              (v) =>
                  store.updateSettings((settings) => settings..autoGroupAI = v),
            ),
            _toggle(
              context,
              t['suppressGroupPrompt']!,
              null,
              store.settings.suppressGroupPrompt,
              (v) => store.updateSettings(
                (settings) => settings..suppressGroupPrompt = v,
              ),
            ),
            _toggle(
              context,
              t['autoCompleteParent']!,
              t['autoCompleteParentDesc']!,
              store.settings.autoCompleteParent,
              (v) => store.updateSettings(
                (settings) => settings..autoCompleteParent = v,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    t['urgencyThreshold']!,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                Text(
                  '${store.settings.urgencyThresholdDays}${t['daysLeft']}',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            Slider(
              min: 1,
              max: 14,
              divisions: 13,
              value: store.settings.urgencyThresholdDays.toDouble(),
              onChanged:
                  (v) => store.updateSettings(
                    (settings) => settings..urgencyThresholdDays = v.round(),
                  ),
            ),
            const SizedBox(height: 20),

            _sectionTitle(theme, t['provider']!, Icons.smart_toy_outlined),
            DropdownButton<AIProtocol>(
              isExpanded: true,
              items: [
                DropdownMenuItem(
                  value: AIProtocol.openai,
                  child: Text(
                    t['providerOpenAI']!,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                DropdownMenuItem(
                  value: AIProtocol.openaiResponses,
                  child: Text(
                    t['providerOpenAIResponses']!,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                DropdownMenuItem(
                  value: AIProtocol.anthropic,
                  child: Text(
                    t['providerAnthropic']!,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              value: store.aiConfig.protocol,
              onChanged: (value) {
                if (value != null) {
                  store.updateAIConfig(store.aiConfig..protocol = value);
                }
              },
            ),
            const SizedBox(height: 12),
            TextField(
              autocorrect: false,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(labelText: t['customBaseUrl']),
              controller: _baseUrlController,
              onChanged:
                  (v) => store.updateAIConfig(store.aiConfig..baseUrl = v),
            ),
            const SizedBox(height: 10),
            TextField(
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(labelText: t['customApiKey']),
              obscureText: true,
              controller: _apiKeyController,
              onChanged:
                  (v) => store.updateAIConfig(store.aiConfig..apiKey = v),
            ),
            const SizedBox(height: 10),
            TextField(
              decoration: InputDecoration(labelText: t['customModel']),
              controller: _modelController,
              onChanged: (v) => store.updateAIConfig(store.aiConfig..model = v),
            ),
            const SizedBox(height: 6),
            Text(
              t['customUrlHint']!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
              ),
            ),
            const SizedBox(height: 10),
            _TestConnectionButton(t: t, store: store),
            const SizedBox(height: 20),

            _sectionTitle(
              theme,
              t['dataManagement']!,
              Icons.cloud_sync_outlined,
            ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.download_outlined, size: 18),
                    label: Text(t['exportData']!),
                    onPressed: _fileBusy ? null : () => _export(context, store),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.upload_outlined, size: 18),
                    label: Text(t['importData']!),
                    onPressed: _fileBusy ? null : () => _import(context, store),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(ThemeData theme, String text, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toggle(
    BuildContext context,
    String title,
    String? subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(title, style: Theme.of(context).textTheme.bodyMedium),
      subtitle:
          subtitle == null
              ? null
              : Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
      value: value,
      onChanged: onChanged,
    );
  }

  Future<void> _export(BuildContext context, Store store) async {
    if (_fileBusy) return;
    setState(() => _fileBusy = true);
    try {
      final bytes = Uint8List.fromList(utf8.encode(store.exportJson()));
      final path = await FilePicker.platform.saveFile(
        fileName:
            'matrixflow_backup_${DateTime.now().toIso8601String().split('T').first}.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: bytes,
      );
      if (path == null) return;
      // Android's Storage Access Framework writes the bytes itself. Its return
      // value may be a content URI, not a Dart File path.
      if (!Platform.isAndroid && !Platform.isIOS) {
        await File(path).writeAsBytes(bytes, flush: true);
      }
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(path)));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(store.t['exportError']!)));
      }
    } finally {
      if (mounted) setState(() => _fileBusy = false);
    }
  }

  Future<void> _import(BuildContext context, Store store) async {
    if (_fileBusy) return;
    setState(() => _fileBusy = true);
    final t = store.t;
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      if (!context.mounted || picked == null) return;
      final file = picked.files.single;
      final bytes =
          file.bytes ??
          (file.path == null ? null : await File(file.path!).readAsBytes());
      if (bytes == null) throw const FormatException('No file data');
      final json = jsonDecode(
        utf8.decode(bytes).replaceFirst(RegExp(r'^\uFEFF'), ''),
      );
      if (json is! Map<String, dynamic> ||
          json['boards'] is! List ||
          json['tasks'] is! List) {
        throw const FormatException('bad shape');
      }
      if (!context.mounted) return;
      final mode = await showDialog<String>(
        context: context,
        builder:
            (dialogContext) => AlertDialog(
              title: Text(t['importOptions']!),
              content: Text(t['importPrompt']!),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(t['cancel']!),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, 'merge'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t['importModeMerge']!),
                      Text(
                        t['importModeMergeDesc']!,
                        style: Theme.of(dialogContext).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                  ),
                  onPressed: () => Navigator.pop(dialogContext, 'overwrite'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t['importModeOverwrite']!),
                      Text(
                        t['importModeOverwriteDesc']!,
                        style: Theme.of(dialogContext).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
      );
      if (mode == null || !context.mounted) return;
      if (mode == 'overwrite') {
        final sure = await showDialog<bool>(
          context: context,
          builder:
              (dialogContext) => AlertDialog(
                content: Text(t['confirmImport']!),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: Text(t['cancel']!),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error,
                    ),
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: Text(t['confirm']!),
                  ),
                ],
              ),
        );
        if (sure != true || !context.mounted) return;
      }
      final count = store.importData(json, mode);
      _baseUrlController.text = store.aiConfig.baseUrl;
      _apiKeyController.text = store.aiConfig.apiKey;
      _modelController.text = store.aiConfig.model;
      await store.flush();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              store.persistenceError ?? '${store.t['importSuccess']} ($count)',
            ),
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(t['importError']!)));
      }
    } finally {
      if (mounted) setState(() => _fileBusy = false);
    }
  }
}

class _ColorDot extends StatelessWidget {
  final Color color;
  final bool selected;
  final String tooltip;
  final VoidCallback onTap;
  const _ColorDot({
    required this.color,
    required this.selected,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        width: selected ? 34 : 28,
        height: selected ? 34 : 28,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border:
              selected
                  ? Border.all(
                    width: 3,
                    color: Theme.of(context).colorScheme.surface,
                  )
                  : null,
          boxShadow:
              selected
                  ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.5),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ]
                  : null,
        ),
        child:
            selected
                ? const Icon(Icons.check, size: 16, color: Colors.white)
                : null,
      ),
    ).gestures(onTap: onTap);
  }
}

extension _Gestures on Widget {
  Widget gestures({VoidCallback? onTap}) =>
      GestureDetector(onTap: onTap, child: this);
}

class _TestConnectionButton extends StatefulWidget {
  final Map<String, String> t;
  final Store store;
  const _TestConnectionButton({required this.t, required this.store});

  @override
  State<_TestConnectionButton> createState() => _TestConnectionButtonState();
}

class _TestConnectionButtonState extends State<_TestConnectionButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: _busy ? null : _run,
      icon:
          _busy
              ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
              : const Icon(Icons.wifi_tethering, size: 18),
      label: Text(
        _busy ? widget.t['processing']! : widget.t['testConnection']!,
      ),
    );
  }

  Future<void> _run() async {
    setState(() => _busy = true);
    final result = await widget.store.ai.testConnection(
      AIConfig.fromJson(widget.store.aiConfig.toJson()),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.ok
              ? widget.t['testOk']!
              : widget.t[result.message] ??
                  '${widget.t['testFail']} (${result.message})',
        ),
        backgroundColor:
            result.ok
                ? Colors.green.shade600
                : Theme.of(context).colorScheme.error,
      ),
    );
  }
}
