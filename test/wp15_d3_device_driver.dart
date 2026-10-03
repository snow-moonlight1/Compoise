import 'dart:convert';
import 'dart:io';
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  timeout: const Duration(minutes: 12),
  writeResponseOnFailure: true,
  responseDataCallback: (data) async {
    final native = data?['native'] as Map?;
    if (data == null ||
        data['commit'] != Platform.environment['WP15_D3_EXPECTED_COMMIT'] ||
        data['platform'] != 'windows' ||
        native?['namespace'] != Platform.environment['WP15_D3_NAMESPACE'] ||
        native?['root'] != Platform.environment['WP15_D3_ROOT'] ||
        native?['pid'] !=
            int.parse(Platform.environment['WP15_D3_EXPECTED_PID']!)) {
      throw StateError(
        'Driver response is not from this isolated Windows process',
      );
    }
    await File(
      '${Platform.environment['WP15_D3_ROOT']}/driver-result.json',
    ).writeAsString(jsonEncode(data), flush: true);
    stdout.writeln('WP15_D3_RESULT platform=windows commit=${data['commit']}');
  },
);
