import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/storage.dart';

class _TestCredentialStore implements CredentialStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async {
    this.value = value;
  }

  @override
  Future<void> delete() async {
    value = null;
  }
}

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  setUp(() {
    Store.testCredentialStore = _TestCredentialStore();
  });
  await testMain();
}
