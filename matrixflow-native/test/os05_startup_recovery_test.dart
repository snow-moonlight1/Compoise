import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/screens/startup_recovery_screen.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RecoveryPicker extends FilePicker {
  Uint8List? savedBytes;

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    savedBytes = bytes;
    return null; // Simulate cancelling the platform picker after receiving data.
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('OS05: missing keys initialize normally and are classified', () async {
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    addTearDown(store.dispose);
    await store.init();
    await store.flush();
    expect(store.hasStartupRecovery, isFalse);
    expect(
      store.startupDataStates['matrixflow-tasks'],
      StartupDataState.missing,
    );
    expect(store.boards, hasLength(1));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('matrixflow-boards'), isNotNull);
  });

  test(
    'OS-R01: truncated task source survives startup and repeated restart',
    () async {
      const damaged = '[{"id":"synthetic","title":"unfinished';
      const healthyBoards = '[{"id":"b","name":"B","createdAt":1}]';
      SharedPreferences.setMockInitialValues({
        'matrixflow-tasks': damaged,
        'matrixflow-boards': healthyBoards,
        'matrixflow-has-seen-onboarding': true,
      });
      final first = Store();
      await first.init();
      await first.flush();
      expect(first.hasStartupRecovery, isTrue);
      expect(first.recoveryKeys, contains('matrixflow-tasks'));
      expect(
        first.startupDataStates['matrixflow-tasks'],
        StartupDataState.corrupt,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('matrixflow-tasks'), damaged);
      expect(prefs.getString('matrixflow-boards'), healthyBoards);
      first.dispose();

      final second = Store();
      addTearDown(second.dispose);
      await second.init();
      await second.flush();
      expect(second.hasStartupRecovery, isTrue);
      expect(prefs.getString('matrixflow-tasks'), damaged);
    },
  );

  test('OS05: wrong top levels and primitive types remain untouched', () async {
    SharedPreferences.setMockInitialValues({
      'matrixflow-tasks': '{}',
      'matrixflow-boards': '42',
      'matrixflow-config': 7,
      'matrixflow-settings': 'false',
      'matrixflow-has-seen-onboarding': 'true',
      'matrixflow-active-board': 3,
    });
    final store = Store();
    addTearDown(store.dispose);
    await store.init();
    await store.flush();
    expect(store.ready, isTrue);
    expect(store.recoveryKeys, hasLength(6));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('matrixflow-tasks'), '{}');
    expect(prefs.getString('matrixflow-boards'), '42');
    expect(prefs.get('matrixflow-config'), 7);
    expect(prefs.getString('matrixflow-settings'), 'false');
    expect(prefs.get('matrixflow-has-seen-onboarding'), 'true');
    expect(prefs.get('matrixflow-active-board'), 3);
  });

  test(
    'OS05: partial record damage stays recoverable until explicit discard',
    () async {
      final source = jsonEncode([
        {'id': 'good', 'boardId': 'b', 'title': 'Synthetic', 'quadrant': 1},
        {'id': '', 'boardId': 'b', 'title': 'Bad'},
      ]);
      SharedPreferences.setMockInitialValues({
        'matrixflow-boards': '[{"id":"b","name":"B","createdAt":1}]',
        'matrixflow-tasks': source,
      });
      final store = Store();
      addTearDown(store.dispose);
      await store.init();
      expect(store.tasks, hasLength(1));
      expect(store.hasStartupRecovery, isTrue);
      final copy = jsonDecode(store.recoveryCopyJson()) as Map<String, dynamic>;
      expect(copy['format'], 'matrixflow-startup-recovery-v1');
      expect(
        (copy['entries'] as List).where(
          (entry) =>
              entry['key'] == 'matrixflow-tasks' && entry['value'] == source,
        ),
        hasLength(1),
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('matrixflow-tasks'), source);
      expect(await store.discardDamagedStartupData(), isTrue);
      await store.flush();
      expect(store.hasStartupRecovery, isFalse);
      expect(
        jsonDecode(prefs.getString('matrixflow-tasks')!) as List,
        hasLength(1),
      );
    },
  );

  test(
    'OS05: legacy normalized records migrate without recovery lock',
    () async {
      SharedPreferences.setMockInitialValues({
        'matrixflow-boards': '[{"id":"b"}]',
        'matrixflow-tasks': '[{"id":"t","boardId":"b","quadrant":"Q2"}]',
      });
      final store = Store();
      addTearDown(store.dispose);
      await store.init();
      await store.flush();
      expect(store.hasStartupRecovery, isFalse);
      expect(
        store.startupDataStates['matrixflow-tasks'],
        StartupDataState.migrated,
      );
      expect(store.tasks.single.quadrant, 2);
    },
  );

  testWidgets('OS05: cancelling discard keeps recovery screen and source', (
    tester,
  ) async {
    const source = '[{"id":"unfinished"';
    SharedPreferences.setMockInitialValues({'matrixflow-tasks': source});
    final store = Store();
    addTearDown(store.dispose);
    await store.init();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: store,
        child: const MaterialApp(home: StartupRecoveryScreen()),
      ),
    );
    expect(find.text(store.t['recoveryTitle']!), findsOneWidget);
    await tester.tap(
      find.widgetWithText(OutlinedButton, store.t['recoveryDiscard']!),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(store.t['cancel']!));
    await tester.pumpAndSettle();
    expect(store.hasStartupRecovery, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('matrixflow-tasks'), source);
    expect(find.text(store.t['recoveryTitle']!), findsOneWidget);
  });

  testWidgets('OS05: recovery save sends original values to the picker', (
    tester,
  ) async {
    const source = '[{"id":"unfinished"';
    SharedPreferences.setMockInitialValues({
      'matrixflow-tasks': source,
      'matrixflow-settings': '{"language":"en"}',
    });
    final store = Store();
    addTearDown(store.dispose);
    await store.init();
    final picker = _RecoveryPicker();
    FilePicker.platform = picker;
    addTearDown(() => FilePicker.platform = _RecoveryPicker());
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: store,
        child: const MaterialApp(home: StartupRecoveryScreen()),
      ),
    );
    await tester.tap(find.text(store.t['recoverySave']!));
    await tester.pumpAndSettle();
    final copy =
        jsonDecode(utf8.decode(picker.savedBytes!)) as Map<String, dynamic>;
    expect(copy['format'], 'matrixflow-startup-recovery-v1');
    expect(
      copy['entries'],
      contains(
        allOf(
          containsPair('key', 'matrixflow-tasks'),
          containsPair('value', source),
        ),
      ),
    );
    expect(
      copy['entries'],
      contains(
        allOf(
          containsPair('key', 'matrixflow-settings'),
          containsPair('value', '{"language":"en"}'),
        ),
      ),
    );
    expect(store.hasStartupRecovery, isTrue);
    expect(find.text(source), findsNothing);
  });
}
