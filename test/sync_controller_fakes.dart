// Fakes for driving SyncController: a listenable library, memory secure
// storage and hand-fired timers.
import 'dart:async';

import 'package:compoise/credential_store.dart';
import 'package:compoise/sync/sync_engine.dart';
import 'package:compoise/sync/sync_library.dart';
import 'package:compoise/sync/sync_store_host.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sync_fakes.dart';

class SourceHost extends FakeHost
    with ChangeNotifier
    implements SyncLibrarySource {
  int appliedRevision = -1;
  bool durable = true;

  @override
  int get syncRevision => revision;

  @override
  int get syncAppliedRevision => appliedRevision;

  @override
  bool get syncLibraryDurable => durable;

  @override
  Future<void> settle() async {}

  @override
  Future<SyncApplyOutcome> apply(int baseRevision, SyncLibrary library) async {
    final outcome = await super.apply(baseRevision, library);
    if (outcome == SyncApplyOutcome.applied) {
      appliedRevision = revision;
      notifyListeners();
    }
    return outcome;
  }

  void userEdit(String id, String title) {
    addTask(id, title);
    notifyListeners();
  }
}

class MemoryCredentials implements CredentialStore {
  String? value;
  bool failRead = false;

  @override
  Future<String?> read() async {
    if (failRead) throw StateError('keyring locked');
    return value;
  }

  @override
  Future<void> write(String next) async => value = next;

  @override
  Future<void> delete() async => value = null;
}

class ManualTimer implements Timer {
  ManualTimer(this.delay, this.callback);

  final Duration delay;
  final void Function() callback;
  bool _active = true;

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;

  @override
  void cancel() => _active = false;
}

class ManualTimers {
  final List<ManualTimer> _all = [];

  Timer call(Duration delay, void Function() callback) {
    final timer = ManualTimer(delay, callback);
    _all.add(timer);
    return timer;
  }

  List<Duration> get active => [
    for (final timer in _all)
      if (timer.isActive) timer.delay,
  ];

  /// Fires every active timer with [delay], then lets the work settle.
  Future<void> fire(Duration delay) async {
    final due = [
      for (final timer in _all)
        if (timer.isActive && timer.delay == delay) timer,
    ];
    expect(due, isNotEmpty, reason: 'no active $delay timer in $active');
    for (final timer in due) {
      timer._active = false;
      timer.callback();
    }
    await settle();
  }
}

Future<void> settle() async {
  for (var i = 0; i < 200; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
