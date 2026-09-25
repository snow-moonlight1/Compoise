import 'package:flutter/foundation.dart';
import '../models.dart';

enum DesktopShellResultKind {
  success,
  disabled,
  unsupported,
  unavailable,
  conflict,
  invalid,
  superseded,
}

@immutable
class DesktopShellResult {
  final DesktopShellResultKind kind;
  final String? detail;

  const DesktopShellResult(this.kind, {this.detail});

  const DesktopShellResult.success() : this(DesktopShellResultKind.success);

  const DesktopShellResult.disabled() : this(DesktopShellResultKind.disabled);

  const DesktopShellResult.unsupported()
    : this(DesktopShellResultKind.unsupported);

  const DesktopShellResult.superseded()
    : this(DesktopShellResultKind.superseded);

  bool get succeeded => kind == DesktopShellResultKind.success;

  bool get isFailure => switch (kind) {
    DesktopShellResultKind.unavailable ||
    DesktopShellResultKind.conflict ||
    DesktopShellResultKind.invalid => true,
    _ => false,
  };
}

class DesktopShellHostCallbacks {
  final Language language;
  final VoidCallback onWindowCloseRequested;
  final VoidCallback onRestoreRequested;
  final VoidCallback? onQuickAddRequested;
  final VoidCallback? onSearchRequested;
  final VoidCallback? onExitRequested;

  const DesktopShellHostCallbacks({
    this.language = Language.en,
    required this.onWindowCloseRequested,
    required this.onRestoreRequested,
    this.onQuickAddRequested,
    this.onSearchRequested,
    this.onExitRequested,
  });
}

abstract class DesktopShellHost {
  String? get registeredShortcut;

  Future<DesktopShellResult> start(DesktopShellHostCallbacks callbacks);

  Future<DesktopShellResult> registerHotkey(
    String shortcut,
    VoidCallback onTrigger,
  );

  Future<DesktopShellResult> unregisterHotkey();

  Future<DesktopShellResult> hide();

  Future<DesktopShellResult> show();

  Future<void> destroy();
}
