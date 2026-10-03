import 'dart:convert';
import 'dart:io';
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  timeout: const Duration(minutes: 15),
  responseDataCallback: (data) async {
    final output = Platform.environment['WP17_I6_REPORT'];
    if (output == null || data == null) {
      throw StateError('WP17_I6_REPORT is required');
    }
    await File(
      output,
    ).writeAsString('${const JsonEncoder.withIndent('  ').convert(data)}\n');
  },
);
