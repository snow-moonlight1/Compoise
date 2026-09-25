import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/services/reminder_service.dart';
import 'package:matrixflow_native/services/single_instance.dart';

void main() {
  group('OS16 single-instance arguments', () {
    test('decodes a percent-encoded notification payload', () {
      final payload = ReminderPayload(
        boardId: 'board-1',
        taskId: 'task-1',
        subtaskId: 'sub-1',
      );
      final decoded = notificationPayloadFromArguments([
        '--unrelated',
        encodeNotificationPayloadArgument(payload),
      ]);
      expect(decoded, payload);
    });

    test('accepts a raw JSON payload argument', () {
      final decoded = notificationPayloadFromArguments([
        '--matrixflow-notification-payload={"boardId":"b","taskId":"t"}',
      ]);
      expect(decoded?.boardId, 'b');
      expect(decoded?.taskId, 't');
      expect(decoded?.subtaskId, isNull);
    });

    test('ignores unrelated arguments and malformed payloads', () {
      expect(
        notificationPayloadFromArguments(['--enable-dart-profiling']),
        isNull,
      );
      expect(
        notificationPayloadFromArguments([
          '--matrixflow-notification-payload=not-json',
        ]),
        isNull,
      );
      expect(
        notificationPayloadFromArguments([
          '--matrixflow-notification-payload=',
        ]),
        isNull,
      );
    });

    test('restores the window and delivers a real task id', () {
      var restored = 0;
      ReminderPayload? delivered;
      dispatchSingleInstanceActivation(
        [
          encodeNotificationPayloadArgument(
            const ReminderPayload(boardId: 'b', taskId: 't', subtaskId: 's'),
          ),
        ],
        restoreWindow: () => restored++,
        deliverPayload: (payload) => delivered = payload,
      );
      expect(restored, 1);
      expect(delivered?.taskId, 't');
      expect(delivered?.subtaskId, 's');
    });

    test('restores without delivering when the launch has no task', () {
      var restored = 0;
      var delivered = 0;
      dispatchSingleInstanceActivation(
        const ['--matrixflow-notification-payload={"boardId":"b","taskId":""}'],
        restoreWindow: () => restored++,
        deliverPayload: (_) => delivered++,
      );
      dispatchSingleInstanceActivation(
        const [],
        restoreWindow: () => restored++,
        deliverPayload: (_) => delivered++,
      );
      expect(restored, 2);
      expect(delivered, 0);
    });

    test('primary install delivers only its own notification argument', () async {
      final seen = <List<String>>[];
      await SingleInstanceController.install(
        initialArguments: [
          '--enable-dart-profiling',
          encodeNotificationPayloadArgument(
            const ReminderPayload(boardId: 'b', taskId: 'cold'),
          ),
        ],
        onActivated: seen.add,
      );
      expect(seen, hasLength(1));
      expect(seen.single.last, contains('cold'));
    });
  });
}
