import 'dart:convert';
import 'dart:io';

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
      body: ListView(
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
            onSelectionChanged: (s) =>
                store.updateSettings((settings) => settings..language = s.first),
          ),
          const SizedBox(height: 20),

          _sectionTitle(theme, t['theme']!, Icons.brightness_6_outlined),
          SegmentedButton<ThemeModePref>(
            segments: [
              ButtonSegment(value: ThemeModePref.light, icon: const Icon(Icons.light_mode, size: 16), label: Text(t['themeLight']!)),
              ButtonSegment(value: ThemeModePref.dark, icon: const Icon(Icons.dark_mode, size: 16), label: Text(t['themeDark']!)),
              ButtonSegment(value: ThemeModePref.system, icon: const Icon(Icons.settings_suggest_outlined, size: 16), label: Text(t['themeSystem']!)),
            ],
            selected: {store.settings.theme},
            onSelectionChanged: (s) =>
                store.updateSettings((settings) => settings..theme = s.first),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final color in ThemeColor.values)
                _ColorDot(
                  color: themeSeedColors[color]!,
                  selected: store.settings.themeColor == color,
                  tooltip: t['color${color.name[0].toUpperCase()}${color.name.substring(1)}']!,
                  onTap: () => store.updateSettings((settings) => settings..themeColor = color),
                ),
            ],
          ),
          const SizedBox(height: 20),

          _sectionTitle(theme, t['automation']!, Icons.auto_mode_outlined),
          _toggle(context, t['autoDecomposeAI']!, t['autoDecomposeDesc']!,
              store.settings.autoDecomposeAI,
              (v) => store.updateSettings((settings) => settings..autoDecomposeAI = v)),
          _toggle(context, t['suppressLongTermPrompt']!, null,
              store.settings.suppressLongTermPrompt,
              (v) => store.updateSettings((settings) => settings..suppressLongTermPrompt = v)),
          _toggle(context, t['autoGroupAI']!, t['autoGroupDesc']!, store.settings.autoGroupAI,
              (v) => store.updateSettings((settings) => settings..autoGroupAI = v)),
          _toggle(context, t['suppressGroupPrompt']!, null,
              store.settings.suppressGroupPrompt,
              (v) => store.updateSettings((settings) => settings..suppressGroupPrompt = v)),
          _toggle(context, t['autoCompleteParent']!, t['autoCompleteParentDesc']!,
              store.settings.autoCompleteParent,
              (v) => store.updateSettings((settings) => settings..autoCompleteParent = v)),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(t['urgencyThreshold']!, style: theme.textTheme.bodyMedium),
              const Spacer(),
              Text('${store.settings.urgencyThresholdDays}${t['daysLeft']}',
                  style: theme.textTheme.labelLarge
                      ?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w800)),
            ],
          ),
          Slider(
            min: 1,
            max: 14,
            divisions: 13,
            value: store.settings.urgencyThresholdDays.toDouble(),
            onChanged: (v) =>
                store.updateSettings((settings) => settings..urgencyThresholdDays = v.round()),
          ),
          const SizedBox(height: 20),

          _sectionTitle(theme, t['provider']!, Icons.smart_toy_outlined),
          SegmentedButton<AIProtocol>(
            segments: [
              ButtonSegment(value: AIProtocol.openai, label: Text(t['providerOpenAI']!)),
              ButtonSegment(value: AIProtocol.openaiResponses, label: Text(t['providerOpenAIResponses']!)),
              ButtonSegment(value: AIProtocol.anthropic, label: Text(t['providerAnthropic']!)),
            ],
            selected: {store.aiConfig.protocol},
            onSelectionChanged: (s) => store.updateAIConfig(store.aiConfig..protocol = s.first),
          ),
          const SizedBox(height: 12),
          TextField(
            decoration: InputDecoration(labelText: t['customBaseUrl']),
            controller: _baseUrlController,
            onChanged: (v) => store.updateAIConfig(store.aiConfig..baseUrl = v),
          ),
          const SizedBox(height: 10),
          TextField(
            decoration: InputDecoration(labelText: t['customApiKey']),
            obscureText: true,
            controller: _apiKeyController,
            onChanged: (v) => store.updateAIConfig(store.aiConfig..apiKey = v),
          ),
          const SizedBox(height: 10),
          TextField(
            decoration: InputDecoration(labelText: t['customModel']),
            controller: _modelController,
            onChanged: (v) => store.updateAIConfig(store.aiConfig..model = v),
          ),
          const SizedBox(height: 6),
          Text(t['customUrlHint']!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
              )),
          const SizedBox(height: 10),
          _TestConnectionButton(t: t, store: store),
          const SizedBox(height: 20),

          _sectionTitle(theme, t['dataManagement']!, Icons.cloud_sync_outlined),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.download_outlined, size: 18),
                  label: Text(t['exportData']!),
                  onPressed: () => _export(context, store),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.upload_outlined, size: 18),
                  label: Text(t['importData']!),
                  onPressed: () => _import(context, store),
                ),
              ),
            ],
          ),
        ],
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
          Text(text, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _toggle(BuildContext context, String title, String? subtitle, bool value,
      ValueChanged<bool> onChanged) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(title, style: Theme.of(context).textTheme.bodyMedium),
      subtitle: subtitle == null
          ? null
          : Text(subtitle,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5))),
      value: value,
      onChanged: onChanged,
    );
  }

  Future<void> _export(BuildContext context, Store store) async {
    final json = store.exportJson();
    try {
      final path = await FilePicker.platform.saveFile(
        fileName: 'matrixflow_backup_${DateTime.now().toIso8601String().split('T').first}.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (path != null) {
        File(path).writeAsStringSync(json);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(path), width: 460));
        }
        return;
      }
    } catch (_) {
      // fall through to clipboard fallback
    }
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(store.t['exportData']!),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(child: SelectableText(json)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(store.t['close']!)),
        ],
      ),
    );
  }

  Future<void> _import(BuildContext context, Store store) async {
    final t = store.t;
    final picked = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json']);
    if (picked == null || picked.files.single.path == null) return;
    try {
      final json = jsonDecode(File(picked.files.single.path!).readAsStringSync());
      if (json is! Map<String, dynamic> || json['boards'] is! List || json['tasks'] is! List) {
        throw const FormatException('bad shape');
      }
      if (!context.mounted) return;
      final mode = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(t['importOptions']!),
          content: Text(t['importPrompt']!),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(t['cancel']!)),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'merge'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [Text(t['importModeMerge']!), Text(t['importModeMergeDesc']!, style: Theme.of(dialogContext).textTheme.bodySmall)],
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
              onPressed: () => Navigator.pop(dialogContext, 'overwrite'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [Text(t['importModeOverwrite']!), Text(t['importModeOverwriteDesc']!, style: Theme.of(dialogContext).textTheme.bodySmall)],
              ),
            ),
          ],
        ),
      );
      if (mode == null || !context.mounted) return;
      if (mode == 'overwrite') {
        final sure = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            content: Text(t['confirmImport']!),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(t['cancel']!)),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(t['confirm']!),
              ),
            ],
          ),
        );
        if (sure != true) return;
      }
      final count = store.importData(json, mode);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${t['importSuccess']} ($count)'), width: 420),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${t['importError']} ($e)'), width: 460),
        );
      }
    }
  }
}

class _ColorDot extends StatelessWidget {
  final Color color;
  final bool selected;
  final String tooltip;
  final VoidCallback onTap;
  const _ColorDot({required this.color, required this.selected, required this.tooltip, required this.onTap});

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
          border: selected ? Border.all(width: 3, color: Theme.of(context).colorScheme.surface) : null,
          boxShadow: selected
              ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 10, spreadRadius: 1)]
              : null,
        ),
        child: selected ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
      ),
    ).gestures(onTap: onTap);
  }
}

extension _Gestures on Widget {
  Widget gestures({VoidCallback? onTap}) => GestureDetector(onTap: onTap, child: this);
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
      icon: _busy
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.wifi_tethering, size: 18),
      label: Text(_busy ? widget.t['processing']! : widget.t['testConnection']!),
    );
  }

  Future<void> _run() async {
    setState(() => _busy = true);
    final result = await widget.store.ai.testConnection(widget.store.aiConfig);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        width: 460,
        content: Text(result.message),
        backgroundColor: result.ok ? Colors.green.shade600 : Theme.of(context).colorScheme.error,
      ),
    );
  }
}
