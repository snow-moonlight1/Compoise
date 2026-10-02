import 'dart:io';
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  timeout: const Duration(minutes: 12),
  responseDataCallback: (data) async {
    if (data == null || data['commit'] == null || data['platform'] == null) {
      throw StateError('Device run did not report platform/revision evidence');
    }
    // Only synthetic platform metadata; the runner captures the actual exit.
    stdout.writeln('WP15_D2_RESULT $data');
  },
);
