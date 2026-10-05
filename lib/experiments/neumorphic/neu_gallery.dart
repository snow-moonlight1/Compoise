import 'package:flutter/material.dart';

import '../../models.dart';
import '../../theme.dart';
import 'neu_button.dart';
import 'neu_copy.dart';
import 'neu_field.dart';
import 'neu_palette.dart';
import 'neu_toolbar.dart';

enum NeuScene { single, steps, note }

enum NeuSkin { material, neumorphic }

/// Side-by-side or toggled comparison of the current Material theme and the
/// neumorphic experiment. It does not read or write the task store.
class NeuGallery extends StatefulWidget {
  const NeuGallery({
    super.key,
    this.initialScene = NeuScene.single,
    this.showBackButton = false,
  });

  final NeuScene initialScene;

  /// Settings opens the comparison inside the app. The standalone demo does not.
  final bool showBackButton;

  @override
  State<NeuGallery> createState() => NeuGalleryState();
}

class NeuGalleryState extends State<NeuGallery> {
  Brightness? _brightness;
  bool? _highContrast;
  bool? _reduceMotion;
  Locale? _locale;
  NeuScene? _scene;
  NeuSkin _narrowSkin = NeuSkin.neumorphic;
  String? _status;
  String? _deleteError;
  late final TextEditingController _neuNote = TextEditingController();
  late final TextEditingController _materialNote = TextEditingController();

  @override
  void dispose() {
    _neuNote.dispose();
    _materialNote.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ambient = MediaQuery.of(context);
    final brightness = _brightness ?? Theme.of(context).brightness;
    final highContrast = _highContrast ?? ambient.highContrast;
    final reduceMotion = _reduceMotion ?? ambient.disableAnimations;
    final scene = _scene ?? widget.initialScene;
    final locale = _locale ?? Localizations.localeOf(context);
    final copy = NeuCopy.of(locale);
    final theme = buildTheme(brightness, ThemeColor.blue);
    final status = _status ?? copy.idleStatus;

    return Localizations.override(
      context: context,
      locale: locale,
      child: Theme(
        data: theme,
        child: MediaQuery(
          data: ambient.copyWith(
            highContrast: highContrast,
            disableAnimations: reduceMotion,
          ),
          child: Scaffold(
            backgroundColor: NeuSpec.resolve(
              brightness: brightness,
              highContrast: highContrast,
              reduceMotion: reduceMotion,
            ).canvas,
            appBar: widget.showBackButton
                ? AppBar(title: Text(copy.galleryTitle))
                : null,
            body: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 720;
                return SingleChildScrollView(
                  key: const Key('uiexp1-scroll'),
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      NeuToolbar(
                        title: copy.galleryTitle,
                        actions: [
                          NeuToolbarAction(
                            buttonKey: const Key('uiexp1-toolbar-compare'),
                            label: copy.compare,
                            icon: Icons.compare_arrows,
                            onPressed: () =>
                                setState(() => _status = copy.compare),
                          ),
                        ],
                      ),
                      _controls(
                        copy,
                        brightness,
                        highContrast,
                        reduceMotion,
                        locale,
                        scene,
                        wide,
                      ),
                      const SizedBox(height: 12),
                      Text(status, key: const Key('uiexp1-status')),
                      const SizedBox(height: 12),
                      if (wide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _skin(copy, scene, NeuSkin.material),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _skin(copy, scene, NeuSkin.neumorphic),
                            ),
                          ],
                        )
                      else
                        _skin(copy, scene, _narrowSkin),
                      const SizedBox(height: 16),
                      Text(
                        copy.stateMatrixTitle,
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      _matrix(copy),
                      const SizedBox(height: 16),
                      Text(
                        copy.recommendation,
                        key: const Key('uiexp1-recommendation'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _controls(
    NeuCopy copy,
    Brightness brightness,
    bool highContrast,
    bool reduceMotion,
    Locale locale,
    NeuScene scene,
    bool wide,
  ) {
    final dark = brightness == Brightness.dark;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _choice(
          key: const Key('uiexp1-toggle-brightness'),
          label: dark ? copy.light : copy.dark,
          selected: dark,
          onPressed: () => setState(() {
            _brightness = dark ? Brightness.light : Brightness.dark;
          }),
        ),
        _choice(
          key: const Key('uiexp1-toggle-contrast'),
          label: copy.highContrast,
          selected: highContrast,
          onPressed: () => setState(() => _highContrast = !highContrast),
        ),
        _choice(
          key: const Key('uiexp1-toggle-motion'),
          label: copy.reduceMotion,
          selected: reduceMotion,
          onPressed: () => setState(() => _reduceMotion = !reduceMotion),
        ),
        _choice(
          key: const Key('uiexp1-locale-zh'),
          label: '中文',
          selected: locale.languageCode == 'zh',
          onPressed: () => setState(() => _locale = const Locale('zh')),
        ),
        _choice(
          key: const Key('uiexp1-locale-en'),
          label: 'English',
          selected: locale.languageCode == 'en',
          onPressed: () => setState(() => _locale = const Locale('en')),
        ),
        _choice(
          key: const Key('uiexp1-locale-ja'),
          label: '日本語',
          selected: locale.languageCode == 'ja',
          onPressed: () => setState(() => _locale = const Locale('ja')),
        ),
        _choice(
          key: const Key('uiexp1-scene-single'),
          label: copy.sceneSingle,
          selected: scene == NeuScene.single,
          onPressed: () => setState(() => _scene = NeuScene.single),
        ),
        _choice(
          key: const Key('uiexp1-scene-steps'),
          label: copy.sceneSteps,
          selected: scene == NeuScene.steps,
          onPressed: () => setState(() => _scene = NeuScene.steps),
        ),
        _choice(
          key: const Key('uiexp1-scene-note'),
          label: copy.sceneNote,
          selected: scene == NeuScene.note,
          onPressed: () => setState(() => _scene = NeuScene.note),
        ),
        if (!wide) ...[
          _choice(
            key: const Key('uiexp1-show-material'),
            label: copy.material,
            selected: _narrowSkin == NeuSkin.material,
            onPressed: () => setState(() => _narrowSkin = NeuSkin.material),
          ),
          _choice(
            key: const Key('uiexp1-show-neu'),
            label: copy.neumorphic,
            selected: _narrowSkin == NeuSkin.neumorphic,
            onPressed: () => setState(() => _narrowSkin = NeuSkin.neumorphic),
          ),
        ],
      ],
    );
  }

  Widget _choice({
    required Key key,
    required String label,
    required bool selected,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: 180,
      child: NeuButton(
        key: key,
        label: label,
        role: NeuRole.secondary,
        selected: selected,
        onPressed: onPressed,
      ),
    );
  }

  Widget _skin(NeuCopy copy, NeuScene scene, NeuSkin skin) {
    final neu = skin == NeuSkin.neumorphic;
    final prefix = neu ? 'uiexp1-neu' : 'uiexp1-material';
    return KeyedSubtree(
      key: Key(neu ? 'uiexp1-skin-neu' : 'uiexp1-skin-material'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            neu ? copy.neumorphic : copy.material,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          ..._hierarchy(copy, scene, prefix),
          const SizedBox(height: 8),
          neu
              ? NeuField(
                  key: Key('$prefix-note'),
                  label: copy.noteLabel,
                  controller: _neuNote,
                  minLines: 2,
                  maxLines: 4,
                )
              : TextField(
                  key: Key('$prefix-note'),
                  controller: _materialNote,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(labelText: copy.noteLabel),
                ),
          const SizedBox(height: 8),
          _action(
            neu: neu,
            buttonKey: Key('$prefix-save'),
            label: copy.save,
            icon: Icons.check,
            role: NeuRole.primary,
            onPressed: () => setState(() => _status = copy.statusSaved),
          ),
          const SizedBox(height: 8),
          _action(
            neu: neu,
            buttonKey: Key('$prefix-schedule'),
            label: copy.schedule,
            icon: Icons.schedule,
            role: NeuRole.secondary,
            onPressed: () => setState(() => _status = copy.statusScheduled),
          ),
          const SizedBox(height: 8),
          _action(
            neu: neu,
            buttonKey: Key('$prefix-delete'),
            label: copy.delete,
            icon: Icons.delete_outline,
            role: NeuRole.danger,
            errorText: neu ? _deleteError : null,
            onPressed: () => setState(() {
              _deleteError = copy.deleteError;
              _status = copy.statusBlocked;
            }),
          ),
          if (!neu && _deleteError != null) ...[
            const SizedBox(height: 8),
            Text(
              _deleteError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _hierarchy(NeuCopy copy, NeuScene scene, String prefix) {
    final steps = scene == NeuScene.single
        ? <String>[copy.stepOne]
        : <String>[copy.stepOne, copy.stepTwo];
    return [
      Text(switch (scene) {
        NeuScene.single => copy.captionSingle,
        NeuScene.steps => copy.captionSteps,
        NeuScene.note => copy.captionNote,
      }),
      if (scene != NeuScene.single) ...[
        const SizedBox(height: 8),
        Text(copy.parentTitle, style: Theme.of(context).textTheme.titleMedium),
      ],
      const SizedBox(height: 8),
      for (final step in steps)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(value: false, onChanged: (_) {}, semanticLabel: step),
            Expanded(child: Text(step, softWrap: true)),
          ],
        ),
      if (scene == NeuScene.note) ...[
        const SizedBox(height: 8),
        Text(copy.noteBody, key: Key('$prefix-note-body')),
        const SizedBox(height: 8),
        Text(copy.propertySummary),
      ],
    ];
  }

  Widget _action({
    required bool neu,
    required Key buttonKey,
    required String label,
    required IconData icon,
    required NeuRole role,
    required VoidCallback onPressed,
    String? errorText,
  }) {
    if (neu) {
      return NeuButton(
        key: buttonKey,
        label: label,
        icon: icon,
        role: role,
        errorText: errorText,
        onPressed: onPressed,
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final background = switch (role) {
      NeuRole.primary => scheme.primary,
      NeuRole.secondary => null,
      NeuRole.danger => scheme.error,
    };
    final foreground = switch (role) {
      NeuRole.primary => scheme.onPrimary,
      NeuRole.secondary => scheme.onSurface,
      NeuRole.danger => scheme.onError,
    };
    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
      tapTargetSize: MaterialTapTargetSize.padded,
      backgroundColor: background == null
          ? null
          : WidgetStatePropertyAll(background),
      foregroundColor: WidgetStatePropertyAll(foreground),
      side: role == NeuRole.secondary
          ? WidgetStatePropertyAll(BorderSide(color: scheme.outline))
          : null,
    );
    final child = Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text(label, softWrap: true)),
      ],
    );
    final button = role == NeuRole.secondary
        ? OutlinedButton(
            key: buttonKey,
            style: style,
            onPressed: onPressed,
            child: child,
          )
        : FilledButton(
            key: buttonKey,
            style: style,
            onPressed: onPressed,
            child: child,
          );
    return SizedBox(width: double.infinity, child: button);
  }

  Widget _matrix(NeuCopy copy) {
    Widget sample(String name, NeuPaint paint, NeuRole role, {String? error}) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: NeuButton(
          key: Key('uiexp1-matrix-${role.name}-${paint.name}'),
          label: '$name · ${copy.save}',
          role: role,
          paint: paint,
          errorText: error,
          onPressed: paint == NeuPaint.disabled ? null : () {},
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        sample(copy.pressedSample, NeuPaint.pressed, NeuRole.primary),
        sample(copy.focusedSample, NeuPaint.focused, NeuRole.secondary),
        sample(copy.disabledSample, NeuPaint.disabled, NeuRole.secondary),
        sample(
          copy.errorSample,
          NeuPaint.error,
          NeuRole.danger,
          error: copy.deleteError,
        ),
      ],
    );
  }
}
